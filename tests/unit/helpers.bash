setup() {
    umask 022
    DOTFILES_ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
    REAL_CHEZMOI=$(command -v chezmoi)
    REAL_TASK=$(command -v task)
    export FIXTURE="$BATS_TEST_TMPDIR/fixture with spaces"
    mkdir -p "$FIXTURE/bin" "$FIXTURE/shims" "$FIXTURE/zdot"
    chmod go-w "$BATS_TEST_TMPDIR" "$FIXTURE" 2>/dev/null || true
    FIXTURE=$(cd "$FIXTURE" && pwd -P)
    export CALLS="$FIXTURE/calls"
    export HISTFILE="$FIXTURE/history"
    : > "$CALLS"
    export PATH="$FIXTURE/bin:$PATH"
    export CHEZMOI_SOURCE_DIR="$DOTFILES_ROOT/home"
    export SMOKE=1
    cat > "$FIXTURE/config.toml" <<EOF
[data]
hostname = 'macbook-air-m2'
shell = 'zsh'
havesudo = true
[data.tools]
brew = '$FIXTURE/bin/brew'
code = '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
mise = '$FIXTURE/bin/mise'
gh = '$FIXTURE/bin/gh'
task = '$FIXTURE/bin/task'
fzf = '$FIXTURE/bin/fzf'
navi = '$FIXTURE/bin/navi'
notion_cli = '$FIXTURE/bin/ntn'
ohmyposh = '$FIXTURE/bin/ohmyposh'
zoxide = '$FIXTURE/bin/zoxide'
rclone = '$FIXTURE/bin/rclone'
[data.rclone]
listremotes = ['fixture']
[data.rclone.remotes.fixture]
name = 'fixture'
type = 'webdav'
args = ['url=https://example.invalid/a b', 'token=\$literal', "label=it's mine"]
EOF
}

stub() {
    printf '#!/bin/bash\n' > "$FIXTURE/bin/$1"
    cat >> "$FIXTURE/bin/$1"
    chmod +x "$FIXTURE/bin/$1"
}

render() {
    "$REAL_CHEZMOI" --config "$FIXTURE/config.toml" \
        --source "$DOTFILES_ROOT" --refresh-externals=never \
        execute-template "$@"
}

task_run() {
    "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes "$@"
}

startup_stubs() {
    stub mise <<'EOF'
printf 'mise %s\n' "$*" >> "$CALLS"
printf 'export PATH="%s/shims:$PATH"\n' "$FIXTURE"
EOF
    stub brew <<'EOF'
printf 'brew %s\n' "$*" >> "$CALLS"
case "$1" in
    shellenv) printf 'export PATH="%s/bin:$PATH"\n' "$FIXTURE" ;;
    --prefix) printf '%s\n' "$FIXTURE" ;;
esac
EOF
    for name in gh task fzf navi ohmyposh zoxide; do
        stub "$name" <<'EOF'
printf '%s %s\n' "${0##*/}" "$*" >> "$CALLS"
case "${0##*/} $1" in
    'zoxide init') printf 'z() { return 99; }\n' ;;
    'zoxide query') printf '1 /unused\n' ;;
    'fzf --bind') printf '%s\n' "${SELECTION:-}"; exit "${SELECTION_STATUS:-0}" ;;
esac
EOF
    done
}

chezmoi_stub() {
    stub chezmoi <<'EOF'
if [ "$1" = source-path ]; then
    printf '%s/home\n' "$FIXTURE/active source"
else
    printf '%s\n' "$*" >> "$CALLS"
fi
EOF
}
