#!/usr/bin/env bats

load helpers

@test "noninteractive zsh reads XDG defaults without invoking tools" {
    startup_stubs
    render --file "$DOTFILES_ROOT/home/dot_zshenv.tmpl" > "$FIXTURE/zdot/.zshenv"
    run env -u XDG_CACHE_HOME -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
        -u XDG_STATE_HOME -u XDG_DATA_DIRS ZDOTDIR="$FIXTURE/zdot" \
        zsh -d -c 'printf "%s\n" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_DATA_DIRS"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$HOME/.cache" ]
    [ "${lines[1]}" = "$HOME/.config" ]
    [ "${lines[2]}" = "$HOME/.local/share" ]
    [ "${lines[3]}" = "$HOME/.local/state" ]
    [ "${lines[4]}" = '/usr/local/share/:/usr/share/' ]
    [ ! -s "$CALLS" ]
    run env XDG_CACHE_HOME="$FIXTURE/cache" ZDOTDIR="$FIXTURE/zdot" \
        zsh -d -c 'printf "%s\n" "$XDG_CACHE_HOME"'
    [ "$output" = "$FIXTURE/cache" ]
}

@test "login zsh initializes shims last without interactive integrations" {
    startup_stubs
    render --file "$DOTFILES_ROOT/home/dot_zshenv.tmpl" > "$FIXTURE/zdot/.zshenv"
    render --file "$DOTFILES_ROOT/home/dot_zprofile.tmpl" > "$FIXTURE/zdot/.zprofile"
    run env ZDOTDIR="$FIXTURE/zdot" zsh -d -l -c 'printf "%s\n" "${path[1]}"'
    [ "$status" -eq 0 ]
    [ "$output" = "$FIXTURE/shims" ]
    [ "$(cat "$CALLS")" = "$(printf 'brew shellenv\nmise activate zsh --shims')" ]
}

@test "interactive zsh keeps custom z, spaced paths, cancellation, and history" {
    startup_stubs
    render --file "$DOTFILES_ROOT/home/dot_zshrc.tmpl" > "$FIXTURE/zdot/.zshrc"
    mkdir -p "$FIXTURE/selected directory" "$FIXTURE/share/zsh/site-functions"
    printf '#compdef fixture-tool\n' > "$FIXTURE/share/zsh/site-functions/_fixture"
    run env ZDOTDIR="$FIXTURE/zdot" SELECTION="$FIXTURE/selected directory" \
        zsh -d -i -c 'z; printf "%s\n" "$PWD" "$SAVEHIST"; [[ ${_comps[fixture-tool]} == _fixture ]]'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$FIXTURE/selected directory" ]
    [ "${lines[1]}" = 100000 ]
    run env ZDOTDIR="$FIXTURE/zdot" SELECTION_STATUS=130 \
        zsh -d -i -c 'before=$PWD; z; [[ $PWD == $before ]]'
    [ "$status" -eq 0 ]
    ! grep -q -- --shims "$CALLS"
    grep -q '^mise activate zsh$' "$CALLS"
}

@test "Bash wrappers render and the rc guard skips noninteractive setup" {
    startup_stubs
    render --file "$DOTFILES_ROOT/home/dot_bash_profile.tmpl" > "$FIXTURE/profile"
    render --file "$DOTFILES_ROOT/home/dot_bashrc.tmpl" > "$FIXTURE/rc"
    bash -n "$FIXTURE/profile"
    bash -n "$FIXTURE/rc"
    run bash --noprofile --norc -c 'source "$1"' -- "$FIXTURE/rc"
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
    run bash --noprofile --norc -c 'source "$1"; printf "%s\n" "${PATH%%:*}"' -- "$FIXTURE/profile"
    [ "$status" -eq 0 ]
    [ "$output" = "$FIXTURE/shims" ]
    [ "$(cat "$CALLS")" = "$(printf 'brew shellenv\nmise activate bash --shims')" ]
    [ ! -e "$DOTFILES_ROOT/home/dot_bashprofile.tmpl" ]
    mkdir -p "$FIXTURE/selected directory"
    run env SELECTION="$FIXTURE/selected directory" bash --noprofile --rcfile "$FIXTURE/rc" -ic 'z; printf "%s\n" "$PWD"; calc 1+2'
    [ "$status" -eq 0 ]
    [[ "$output" == *"$FIXTURE/selected directory"* ]]
    [[ "$output" == *'1+2 = 3'* ]]
}

@test "Linux templates omit Mac paths and retain cluster cache defaults" {
    startup_stubs
    render '{{ template "startup/profile" (merge (dict "shell" "bash" "os" "linux" "hostname" "raven" "brew" "") .tools) }}' > "$FIXTURE/profile"
    render '{{ template "startup/rc" (merge (dict "shell" "bash" "os" "linux" "hostname" "raven" "brew" "") .tools) }}' > "$FIXTURE/rc"
    bash -n "$FIXTURE/profile"
    bash -n "$FIXTURE/rc"
    run env -u XDG_CACHE_HOME bash --noprofile --norc -c 'source "$1"; printf "%s\n" "$XDG_CACHE_HOME"' -- "$FIXTURE/profile"
    [ "$status" -eq 0 ]
    [ "$output" = "/ptmp/$USER/.cache" ]
    ! grep -Eq 'Visual Studio|lmstudio|pipx-dbt|dbtf' "$FIXTURE/profile"
    grep -q 'module use --append' "$FIXTURE/rc"
    grep -Fq 'trap '\''rm -rf -- "${TMPDIR:?}"'\''' "$FIXTURE/rc"
}

@test "login zsh sets EDITOR safely under set -u and drops dead macOS paths" {
    startup_stubs
    render --file "$DOTFILES_ROOT/home/dot_zshenv.tmpl" > "$FIXTURE/zdot/.zshenv"
    render --file "$DOTFILES_ROOT/home/dot_zprofile.tmpl" > "$FIXTURE/zdot/.zprofile"
    ! grep -Eq 'lmstudio|pipx-dbt' "$FIXTURE/zdot/.zprofile"
    run env -u EDITOR -u VSCODE_INJECTION ZDOTDIR="$FIXTURE/zdot" \
        zsh -u -d -l -c 'printf "%s|%s\n" "$EDITOR" "$RIPGREP_CONFIG_PATH"'
    [ "$status" -eq 0 ]
    [ "$output" = "vi|$HOME/.config/ripgrep/ripgreprc" ]
}

@test "unlisted macOS host with bare code tool does not add dot to PATH" {
    run render --override-data '{"hostname":"macbook-pro","chezmoi":{"os":"darwin"},"tools":{"code":"code"}}' \
        --file "$DOTFILES_ROOT/home/dot_zprofile.tmpl"
    [ "$status" -eq 0 ]
    ! grep -Fq 'PATH="$PATH:."' <<< "$output"
}

@test "login interactive zsh keeps emacs keymap bindings even when EDITOR defaults to vi" {
    startup_stubs
    stub navi <<'EOF'
printf 'navi %s\n' "$*" >> "$CALLS"
printf "bindkey '^g' _navi_widget\n"
EOF
    render --file "$DOTFILES_ROOT/home/dot_zshenv.tmpl" > "$FIXTURE/zdot/.zshenv"
    render --file "$DOTFILES_ROOT/home/dot_zprofile.tmpl" > "$FIXTURE/zdot/.zprofile"
    render --file "$DOTFILES_ROOT/home/dot_zshrc.tmpl" > "$FIXTURE/zdot/.zshrc"
    run env -u EDITOR -u VISUAL -u VSCODE_INJECTION ZDOTDIR="$FIXTURE/zdot" \
        zsh -d -l -i -c 'printf "%s\n" "$EDITOR" "$(bindkey "^G")" "$(bindkey "^I")" "$(bindkey "^[[A")" "$(bindkey "^[[1;3C")"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "vi" ]
    [[ "${lines[1]}" == *'_navi_widget'* ]]
    [[ "${lines[2]}" == *'menu-complete'* ]]
    [[ "${lines[3]}" == *'history-beginning-search-backward'* ]]
    [[ "${lines[4]}" == *'forward-word'* ]]
}

@test "interactive zsh loads ~/.zsh/completions before single compinit and guards optional tools and lern" {
    startup_stubs
    render --file "$DOTFILES_ROOT/home/dot_zshrc.tmpl" > "$FIXTURE/zdot/.zshrc"
    ! grep -q 'compinstall' "$FIXTURE/zdot/.zshrc"
    ! grep -q 'dbtf' "$FIXTURE/zdot/.zshrc"
    [ "$(grep -c 'compinit' "$FIXTURE/zdot/.zshrc")" -eq 2 ] # compinit + bashcompinit

    mkdir -p "$FIXTURE/fake-home/.zsh/completions" "$FIXTURE/fake-home/Developer/projects/personal/lern/lern_app"
    printf '#compdef openspec-fixture\n' > "$FIXTURE/fake-home/.zsh/completions/_openspec-fixture"
    printf 'lern() { printf "lern-loaded\\n"; }\n' > "$FIXTURE/fake-home/Developer/projects/personal/lern/lern_app/shell.zsh"
    run env HOME="$FIXTURE/fake-home" ZDOTDIR="$FIXTURE/zdot" \
        zsh -d -i -c 'lern; [[ ${_comps[openspec-fixture]} == _openspec-fixture ]]'
    [ "$status" -eq 0 ]
    [[ "$output" == *'lern-loaded'* ]]

    # Remove all optional tool stubs and lern script; startup must produce zero stderr
    rm -f "$FIXTURE/bin/gh" "$FIXTURE/bin/task" "$FIXTURE/bin/fzf" "$FIXTURE/bin/navi" "$FIXTURE/bin/ohmyposh" "$FIXTURE/bin/zoxide"
    rm -rf "$FIXTURE/fake-home/Developer"
    run env HOME="$FIXTURE/fake-home" ZDOTDIR="$FIXTURE/zdot" \
        zsh -d -i -c 'exit 0'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
