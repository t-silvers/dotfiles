#!/usr/bin/env bats

load helpers

@test "installer accepts a username and one-shot flag from another directory" {
    stub curl <<'EOF'
printf '200\n'
EOF
    stub uname <<'EOF'
printf 'Linux\n'
EOF
    chezmoi_stub
    stub login-shell <<'EOF'
printf 'shell %s\n' "$*" >> "$CALLS"
EOF
    cd "$FIXTURE"
    run env SHELL="$FIXTURE/bin/login-shell" bash "$DOTFILES_ROOT/install.sh" -g fixture-user -o
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "$(printf 'init --one-shot fixture-user\nshell -l')" ]
}

@test "installer rejects missing and unexpected arguments before running tools" {
    stub curl <<'EOF'
printf 'unexpected network call\n' >> "$CALLS"
exit 99
EOF
    for args in '-g' '-x' '-g fixture-user extra'; do
        # Intentional splitting supplies independent option arguments
        run bash "$DOTFILES_ROOT/install.sh" $args
        [ "$status" -ne 0 ]
        [[ "$output" == *usage:* ]]
    done
    [ ! -s "$CALLS" ]
}

@test "first snapshot copies readable files, excludes .netrc, and counts depth-2 snapshots" {
    mkdir -p "$FIXTURE/dest/nested" "$FIXTURE/new cache/snapshots/dotfiles/2026-10-01/01-00-00" "$FIXTURE/new cache/snapshots/dotfiles/2026-10-01/02-00-00"
    printf 'reviewed contents\n' > "$FIXTURE/dest/nested/read only"
    chmod 400 "$FIXTURE/dest/nested/read only"
    printf 'machine example.invalid login u password secret\n' > "$FIXTURE/dest/.netrc"
    chmod 600 "$FIXTURE/dest/.netrc"
    stub chezmoi <<'EOF'
printf 'SMOKE=%s %s\n' "${SMOKE:-unset}" "$*" >> "$CALLS"
case "$*" in
    "--source $CHEZMOI_SOURCE_DIR --refresh-externals=never managed -i files")
        printf 'nested/read only\n.netrc\n'
        ;;
    *) exit 99 ;;
esac
EOF
    stub sudo <<'EOF'
printf 'unexpected sudo\n' >> "$CALLS"
exit 99
EOF
    run env CHEZMOI_DEST_DIR="$FIXTURE/dest" XDG_CACHE_HOME="$FIXTURE/new cache" \
        bash "$DOTFILES_ROOT/home/.chezmoiscripts/run_before_01-backup-dotfiles.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Number of snapshots: 2'* ]]
    [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
    grep -q '^SMOKE=1 ' "$CALLS"
    local copied
    copied=$(find "$FIXTURE/new cache" -name 'read only')
    cmp "$FIXTURE/dest/nested/read only" "$copied"
    [ -z "$(find "$FIXTURE/new cache" -name '.netrc')" ]
    local manifest
    manifest=$(find "$FIXTURE/new cache" -name 'managed.txt')
    ! grep -q '\.netrc' "$manifest"
}

@test "diff and dry-run preview development source; update-i requires clean checkout and uses ff-only" {
    chezmoi_stub
    run task_run diff
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "--source $DOTFILES_ROOT --refresh-externals=never diff" ]

    : > "$CALLS"
    run task_run dry-run
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "--source $DOTFILES_ROOT --refresh-externals=never apply --dry-run --verbose --force" ]

    # Missing/non-git checkout must abort update-i and interpolate LOCAL_REPO_DIR
    : > "$CALLS"
    run task_run update-i
    [ "$status" -ne 0 ]
    [ ! -s "$CALLS" ]
    [[ "$output" == *"$FIXTURE/active source"* ]]
    [[ "$output" != *'$LOCAL_REPO_DIR'* ]]

    mkdir -p "$FIXTURE/active source"
    git -C "$FIXTURE/active source" init -q
    git -C "$FIXTURE/active source" config user.name "Fixture User"
    git -C "$FIXTURE/active source" config user.email "fixture@example.invalid"
    printf 'tracked\n' > "$FIXTURE/active source/tracked.txt"
    git -C "$FIXTURE/active source" add tracked.txt
    git -C "$FIXTURE/active source" commit -qm "init"

    # Dirty chezmoi checkout must abort update-i before git pull or apply (even under --force)
    printf 'drift\n' > "$FIXTURE/active source/untracked.txt"
    : > "$CALLS"
    run task_run update-i
    [ "$status" -ne 0 ]
    [ ! -s "$CALLS" ]
    run "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes --force update-i
    [ "$status" -ne 0 ]
    [ ! -s "$CALLS" ]

    # Clean chezmoi checkout runs ff-only pull, diff, apply --init
    rm -f "$FIXTURE/active source/untracked.txt"
    : > "$CALLS"
    run task_run update-i
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "$(printf 'git pull -- --ff-only\ndiff\napply --init')" ]

    # Process env SMOKE=0 must not override inline SMOKE=1 on diff
    stub chezmoi <<'EOF'
printf 'SMOKE=%s %s\n' "${SMOKE:-unset}" "$*" >> "$CALLS"
EOF
    : > "$CALLS"
    run env SMOKE=0 "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes diff
    [ "$status" -eq 0 ]
    grep -q '^SMOKE=1 --source ' "$CALLS"
}

@test "brewfile helper quotes FILE with spaces and excludes non-Homebrew runtimes" {
    chezmoi_stub
    stub brew <<'EOF'
printf 'brew %s\n' "$*" >> "$CALLS"
EOF
    run env BREWFILE_OUT="$FIXTURE/wrong" "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" \
        --yes brewfile "FILE=$FIXTURE/my Brewfile"
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "brew bundle dump --no-go --no-uv --no-npm --file=$FIXTURE/my Brewfile --force" ]
}

@test "render selects development templates, handles spaces in FILE and CLI_ARGS, ignores OS FLAGS, and rejects missing files" {
    mkdir -p "$FIXTURE/development/.chezmoitemplates"
    printf 'development marker' > "$FIXTURE/development/.chezmoitemplates/marker"
    printf '{{ template "marker" . }}' > "$FIXTURE/example with spaces.tmpl"
    run env FLAGS='-O2 --bogus' "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes \
        render "DEV_REPO_DIR=$FIXTURE/development" "FILE=$FIXTURE/example with spaces.tmpl" \
        "FLAGS=--config '$FIXTURE/config.toml'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'development marker' ]]

    # Positional CLI_ARGS after -- must handle spaces cleanly via CLI_ARGS_LIST
    run env FLAGS='-O2 --bogus' "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes \
        render "DEV_REPO_DIR=$FIXTURE/development" "FLAGS=--config '$FIXTURE/config.toml'" \
        -- "$FIXTURE/example with spaces.tmpl"
    [ "$status" -eq 0 ]
    [[ "$output" == *'development marker' ]]

    chezmoi_stub
    : > "$CALLS"
    run task_run render "DEV_REPO_DIR=$FIXTURE/development"
    [ "$status" -ne 0 ]
    [[ "$output" == *'FILE is required'* ]]
    [ ! -s "$CALLS" ]

    run task_run render "DEV_REPO_DIR=$FIXTURE/development" "FILE=$FIXTURE/does-not-exist.tmpl"
    [ "$status" -ne 0 ]
    [[ "$output" == *'not found'* ]]
    [ ! -s "$CALLS" ]
}

@test "snapshot deletion rejects traversal and escaping symlinks even under --force or env shadowing and limits valid removal" {
    chezmoi_stub
    mkdir -p "$FIXTURE/snapshots/2026-11-01/12-00-00" "$FIXTURE/snapshots/2026-11-02" "$FIXTURE/outside"
    printf 'keep' > "$FIXTURE/outside/sentinel"
    ln -s "$FIXTURE/outside" "$FIXTURE/snapshots/2026-10-01"
    for invalid in '../outside' '.' '2026-10-01' '2026-11-01/../../outside'; do
        run task_run delete-snapshots "DOTFILES_SNAPSHOT_DIR=$FIXTURE/snapshots" "DATE=$invalid"
        [ "$status" -ne 0 ]
        [ -f "$FIXTURE/outside/sentinel" ]
    done
    # --force must NOT bypass containment guard
    run "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes --force \
        delete-snapshots "DOTFILES_SNAPSHOT_DIR=$FIXTURE/snapshots" "DATE=../outside"
    [ "$status" -ne 0 ]
    [ -f "$FIXTURE/outside/sentinel" ]

    # Process env SNAPSHOT_ROOT / SNAPSHOT_DATE must NOT shadow CLI DATE / DOTFILES_SNAPSHOT_DIR
    run env SNAPSHOT_ROOT="$FIXTURE" SNAPSHOT_DATE="outside" \
        "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes \
        delete-snapshots "DOTFILES_SNAPSHOT_DIR=$FIXTURE/snapshots" DATE=2026-11-01/12-00-00
    [ "$status" -eq 0 ]
    [ ! -e "$FIXTURE/snapshots/2026-11-01/12-00-00" ]
    [ -d "$FIXTURE/snapshots/2026-11-02" ]
    [ -f "$FIXTURE/outside/sentinel" ]

    # installer requires GITHUB_USERNAME explicitly and safely quotes it
    : > "$CALLS"
    run task_run installer
    [ "$status" -ne 0 ]
    [[ "$output" == *'GITHUB_USERNAME'* ]]
    [ ! -s "$CALLS" ]

    run task_run installer "GITHUB_USERNAME=demo-user"
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "generate install-init-shell.sh demo-user" ]
}

@test "rclone uses exact remote names and preserves separate literal arguments" {
    stub rclone <<'EOF'
if [ "$1" = listremotes ]; then
    printf '%s\n' "${EXISTING_REMOTE:-fixture-other:}"
else
    printf '%s\n' "$@" >> "$CALLS"
fi
EOF
    render --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_onchange_after_03-setup-rclone-remotes.sh.tmpl" > "$FIXTURE/remotes.sh"
    run bash "$FIXTURE/remotes.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "$(printf '%s\n' config create fixture webdav 'url=https://example.invalid/a b' 'token=$literal' "label=it's mine")" ]
    : > "$CALLS"
    run env EXISTING_REMOTE=fixture: bash "$FIXTURE/remotes.sh"
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "mise token probe does not print a token" {
    stub mise <<'EOF'
if [ "$1" = token ]; then
    printf 'FIXTURE_SECRET\n'
    printf 'FIXTURE_SECRET\n' >&2
fi
EOF
    render --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_onchange_after_04-install-mise-tools.sh.tmpl" > "$FIXTURE/mise.sh"
    # Stop after the probe; installing tools is outside this check
    sed '/^if \[ ! -f ~\/\.config\/mise\/config.toml \]; then/,$d' "$FIXTURE/mise.sh" > "$FIXTURE/probe.sh"
    run bash "$FIXTURE/probe.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *FIXTURE_SECRET* ]]
}

@test "chezmoiignore scopes shell files and privileged scripts by host capabilities" {
    run render --override-data '{"shell":"bash","havesudo":false,"chezmoi":{"os":"linux"}}' \
        --file "$DOTFILES_ROOT/home/.chezmoiignore.tmpl"
    [ "$status" -eq 0 ]
    [[ "$output" == *'.zlogout'* ]]
    [[ "$output" == *'.zshenv'* ]]
    [[ "$output" == *'.chezmoiscripts/*krb5*'* ]]
    [[ "$output" == *'.chezmoiscripts/*homebrew*'* ]]
    [[ "$output" != *'.bash*'* ]]

    run render --override-data '{"shell":"zsh","havesudo":true,"chezmoi":{"os":"darwin"}}' \
        --file "$DOTFILES_ROOT/home/.chezmoiignore.tmpl"
    [ "$status" -eq 0 ]
    [[ "$output" == *'.bash*'* ]]
    [[ "$output" != *'.zlogout'* ]]
    [[ "$output" != *'.chezmoiscripts/*krb5*'* ]]
}

@test "utils have_sudo handles denial under set -e without revoking valid timestamps" {
    stub sudo <<'EOF'
printf 'sudo %s\n' "$*" >> "$CALLS"
exit "${SUDO_STATUS:-0}"
EOF
    run env SUDO_STATUS=1 bash -euo pipefail -c '
        source "$1"
        if have_sudo; then
            exit 99
        fi
        printf "handled-no-sudo\n"
    ' -- "$DOTFILES_ROOT/utils.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'handled-no-sudo'* ]]

    : > "$CALLS"
    run env SUDO_STATUS=0 bash -euo pipefail -c '
        source "$1"
        have_sudo
    ' -- "$DOTFILES_ROOT/utils.sh"
    [ "$status" -eq 0 ]
    ! grep -q -- '-k' "$CALLS"
}

@test "utils http_request_succeeded reports curl transport failures under set -e" {
    stub curl <<'EOF'
exit 6
EOF
    run bash -euo pipefail -c '
        source "$1"
        http_request_succeeded "https://example.invalid" "Lookup failed"
    ' -- "$DOTFILES_ROOT/utils.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Lookup failed (curl exit 6).'* ]]
}

@test "installer installs chezmoi into ~/.local/bin and stops cleanly when macOS CLT is missing" {
    stub curl <<'EOF'
if [ "$1" = -fsLS ]; then
    printf 'printf "installer %%s\\n" "$*" >> "$CALLS"\n'
else
    printf '200\n'
fi
EOF
    stub uname <<'EOF'
printf 'Linux\n'
EOF
    stub login-shell <<'EOF'
printf 'shell %s\n' "$*" >> "$CALLS"
EOF
    # Build a PATH that has our stubs and basic POSIX utils, but excludes real chezmoi
    mkdir -p "$FIXTURE/no-chezmoi-bin" "$FIXTURE/home"
    for tool in bash env sh mkdir dirname cat date uname curl login-shell; do
        if [ -x "$FIXTURE/bin/$tool" ]; then
            ln -sf "$FIXTURE/bin/$tool" "$FIXTURE/no-chezmoi-bin/$tool"
        elif command -v "$tool" >/dev/null 2>&1; then
            ln -sf "$(command -v "$tool")" "$FIXTURE/no-chezmoi-bin/$tool"
        fi
    done
    run env HOME="$FIXTURE/home" PATH="$FIXTURE/no-chezmoi-bin" SHELL="$FIXTURE/bin/login-shell" \
        bash "$DOTFILES_ROOT/install.sh" -g fixture-user
    [ "$status" -eq 0 ]
    [ -d "$FIXTURE/home/.local/bin" ]
    [ "$(cat "$CALLS")" = "$(printf 'installer -b %s/home/.local/bin init --apply fixture-user\nshell -l' "$FIXTURE")" ]

    : > "$CALLS"
    stub uname <<'EOF'
printf 'Darwin\n'
EOF
    stub xcode-select <<'EOF'
printf 'xcode-select %s\n' "$*" >> "$CALLS"
if [ "$1" = -p ]; then
    exit 2
fi
EOF
    run bash "$DOTFILES_ROOT/install.sh" -g fixture-user
    [ "$status" -ne 0 ]
    [[ "$output" == *'Complete Xcode Command Line Tools installation'* ]]
    grep -q '^xcode-select --install$' "$CALLS"
}

@test "setup-keychain invokes security -w without passing passwords in argv" {
    stub uname <<'EOF'
printf 'Darwin\n'
EOF
    stub security <<'EOF'
printf 'security %s\n' "$*" >> "$CALLS"
if [ "$1" = find-generic-password ]; then
    exit 44
fi
EOF
    run env SMOKE=0 bash "$DOTFILES_ROOT/setup-keychain.sh" "alice:svc"
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "$(printf 'security find-generic-password -a alice -s svc\nsecurity add-generic-password -a alice -s svc -w')" ]

    # Reject malformed pairs before invoking security
    : > "$CALLS"
    for bad in 'nocolon' ':svc' 'alice:'; do
        run env SMOKE=0 bash "$DOTFILES_ROOT/setup-keychain.sh" "$bad"
        [ "$status" -ne 0 ]
        [[ "$output" == *usage:* ]]
    done
    [ ! -s "$CALLS" ]
}

@test "ssh key setup creates missing keys without realpath errors and pipes pubkey via stdin" {
    stub ssh-keygen <<'EOF'
printf 'ssh-keygen %s\n' "$*" >> "$CALLS"
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = -f ]; then
        out="$2"
        shift 2
    else
        shift
    fi
done
printf 'PRIVATE\n' > "$out"
printf 'ssh-rsa AAAAFIXTUREKEY comment\n' > "$out.pub"
EOF
    stub ssh <<'EOF'
stdin_key=$(cat)
printf 'ssh %s | %s\n' "$1" "$stdin_key" >> "$CALLS"
EOF
    render --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_once_before_02-setup-ssh-keys.sh.tmpl" > "$FIXTURE/ssh-keys.sh"
    mkdir -p "$FIXTURE/fresh-home"
    run env HOME="$FIXTURE/fresh-home" bash "$FIXTURE/ssh-keys.sh"
    [ "$status" -eq 0 ]
    [ -d "$FIXTURE/fresh-home/.ssh" ]
    [ -f "$FIXTURE/fresh-home/.ssh/id_rsa_mpimg" ]
    [ -f "$FIXTURE/fresh-home/.ssh/id_rsa_mpiib" ]
    grep -q '^ssh silvers@logan-1\.in\.mpiib-berlin\.mpg\.de | ssh-rsa AAAAFIXTUREKEY comment$' "$CALLS"
}

@test "homebrew uses bash and github auth cleans up temp ssh-agent and skips duplicate keys" {
    render --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_once_after_01-install-homebrew.sh.tmpl" > "$FIXTURE/hb.sh"
    grep -q '^/bin/bash -c ' "$FIXTURE/hb.sh"

    stub ssh-keygen <<'EOF'
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = -f ]; then out="$2"; shift 2; else shift; fi
done
printf 'PRIV\n' > "$out"
printf 'ssh-ed25519 AAAAGHKEY user@example\n' > "$out.pub"
EOF
    stub ssh-agent <<'EOF'
if [ "$1" = -k ]; then
    printf 'ssh-agent -k\n' >> "$CALLS"
else
    printf 'SSH_AUTH_SOCK="%s/agent.sock"; export SSH_AUTH_SOCK;\n' "$FIXTURE"
fi
EOF
    stub ssh-add <<'EOF'
printf 'ssh-add %s\n' "$*" >> "$CALLS"
EOF
    stub gh <<'EOF'
printf 'gh %s\n' "$*" >> "$CALLS"
if [ "$1" = ssh-key ] && [ "$2" = list ]; then
    printf 'My Laptop Key\tssh-ed25519 AAAAGHKEY\t2026-06-01T00:00:00Z\t12345\tsigning\n'
fi
EOF
    render --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_once_after_03-setup-github-auth.sh.tmpl" > "$FIXTURE/gh-auth.sh"
    mkdir -p "$FIXTURE/gh-home"
    run env -u SSH_AUTH_SOCK HOME="$FIXTURE/gh-home" bash "$FIXTURE/gh-auth.sh"
    [ "$status" -eq 0 ]
    grep -q '^ssh-agent -k$' "$CALLS"
    ! grep -q '^gh ssh-key add ' "$CALLS"
}

@test "onchange package scripts hash rendered host output via includeTemplate" {
    mac_hash=$(render --override-data '{"hostname":"macbook-air-m2"}' \
        --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_onchange_after_04-install-mise-tools.sh.tmpl" \
        | grep '^# \.config/mise/config\.toml hash:')
    linux_hash=$(render --override-data '{"hostname":"raven"}' \
        --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_onchange_after_04-install-mise-tools.sh.tmpl" \
        | grep '^# \.config/mise/config\.toml hash:')
    [ -n "$mac_hash" ]
    [ -n "$linux_hash" ]
    [ "$mac_hash" != "$linux_hash" ]

    brew_mac_hash=$(render --override-data '{"hostname":"macbook-air-m2"}' \
        --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_onchange_after_02-install-homebrew-pkgs.sh.tmpl" \
        | grep '^# Brewfile hash:')
    brew_other_hash=$(render --override-data '{"hostname":"macbook-pro"}' \
        --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_onchange_after_02-install-homebrew-pkgs.sh.tmpl" \
        | grep '^# Brewfile hash:')
    [ -n "$brew_mac_hash" ]
    [ -n "$brew_other_hash" ]
    [ "$brew_mac_hash" != "$brew_other_hash" ]
}

@test "chezmoi.toml normalizes raven* and viper* cluster hostnames and falls back for unknown hosts" {
    run "$REAL_CHEZMOI" --source "$DOTFILES_ROOT" --refresh-externals=never \
        execute-template --init \
        --override-data '{"chezmoi":{"os":"linux","hostname":"raven01i"}}' \
        --file -- "$DOTFILES_ROOT/home/.chezmoi.toml.tmpl"
    [ "$status" -eq 0 ]
    grep -Fq 'hostname = "raven"' <<< "$output"
    grep -Fq 'owner = "mpcdf"' <<< "$output"

    run "$REAL_CHEZMOI" --source "$DOTFILES_ROOT" --refresh-externals=never \
        execute-template --init \
        --override-data '{"chezmoi":{"os":"linux","hostname":"viper02i"}}' \
        --file -- "$DOTFILES_ROOT/home/.chezmoi.toml.tmpl"
    [ "$status" -eq 0 ]
    grep -Fq 'hostname = "viper"' <<< "$output"
    grep -Fq 'owner = "mpcdf"' <<< "$output"
}

@test "backup script respects CHEZMOI_EXECUTABLE and CHEZMOI_CONFIG_FILE and fails on chezmoi errors" {
    stub custom-chezmoi <<'EOF'
printf '%s\n' "$*" >> "$CALLS"
exit "${FAIL_STATUS:-0}"
EOF
    run env CHEZMOI_EXECUTABLE="$FIXTURE/bin/custom-chezmoi" \
        CHEZMOI_CONFIG_FILE="$FIXTURE/config.toml" \
        CHEZMOI_DEST_DIR="$FIXTURE/dest" \
        XDG_CACHE_HOME="$FIXTURE/cache" \
        FAIL_STATUS=1 \
        bash "$DOTFILES_ROOT/home/.chezmoiscripts/run_before_01-backup-dotfiles.sh"
    [ "$status" -ne 0 ]
    grep -Fq -- "--config $FIXTURE/config.toml" "$CALLS"
}

@test "github auth still uploads signing key when only an authentication key exists" {
    mkdir -p "$FIXTURE/gh-home/.ssh"
    printf 'PRIV\n' > "$FIXTURE/gh-home/.ssh/id_ed25519_github"
    printf 'ssh-ed25519 AAAAGHKEY user@example\n' > "$FIXTURE/gh-home/.ssh/id_ed25519_github.pub"
    stub gh <<'EOF'
printf 'gh %s\n' "$*" >> "$CALLS"
if [ "$1" = ssh-key ] && [ "$2" = list ]; then
    printf 'My Laptop Key\tssh-ed25519 AAAAGHKEY\t2026-06-01T00:00:00Z\t12345\tauthentication\n'
fi
EOF
    render --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_once_after_03-setup-github-auth.sh.tmpl" > "$FIXTURE/gh-auth.sh"
    run env HOME="$FIXTURE/gh-home" bash "$FIXTURE/gh-auth.sh"
    [ "$status" -eq 0 ]
    grep -q '^gh ssh-key add ' "$CALLS"
}

@test "notion cli setup skips interactive login when already authenticated" {
    stub ntn <<'EOF'
printf 'ntn %s\n' "$*" >> "$CALLS"
if [ "$1" = whoami ]; then
    exit 0
fi
EOF
    render --file "$DOTFILES_ROOT/home/.chezmoiscripts/run_once_after_02-setup-notion-cli.sh.tmpl" > "$FIXTURE/notion.sh"
    run bash "$FIXTURE/notion.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "ntn whoami" ]
}
