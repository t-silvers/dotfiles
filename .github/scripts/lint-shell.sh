#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-.}"
cd "$repo_root"

shopt -s nullglob
scripts=(
  install.sh
  setup-keychain.sh
  utils.sh
  home/.chezmoiscripts/run_before_01-backup-dotfiles.sh
  .github/scripts/*.sh
)
bash_tmpls=(
  home/.chezmoiscripts/run_*.tmpl
  home/dot_bash_profile.tmpl
  home/dot_bashrc.tmpl
)
zsh_tmpls=(
  home/dot_zshenv.tmpl
  home/dot_zprofile.tmpl
  home/dot_zshrc.tmpl
  home/dot_zlogout.tmpl
)

if [[ "${#scripts[@]}" -eq 0 ]]; then
  echo "No shell scripts found to lint" >&2
  exit 1
fi

shellcheck "${scripts[@]}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
tmp_cfg="$tmp_dir/chezmoi.toml"

SMOKE=1 chezmoi --source . --refresh-externals=never \
  execute-template --init --file -- home/.chezmoi.toml.tmpl \
  > "$tmp_cfg"

for tmpl in "${bash_tmpls[@]}"; do
  echo "ShellCheck: $tmpl"
  extra_args=()
  case "$tmpl" in
    *homebrew*)
      brew_data='{"tools":{"brew":"/opt/homebrew/bin/brew"}}'
      extra_args=(--override-data "$brew_data")
      ;;
  esac
  if [[ "${#extra_args[@]}" -gt 0 ]]; then
    SMOKE=1 chezmoi --source . --config "$tmp_cfg" \
      --refresh-externals=never execute-template \
      "${extra_args[@]}" --file -- "$tmpl" \
      | shellcheck -s bash -
  else
    SMOKE=1 chezmoi --source . --config "$tmp_cfg" \
      --refresh-externals=never execute-template --file -- "$tmpl" \
      | shellcheck -s bash -
  fi
done

for tmpl in "${zsh_tmpls[@]}"; do
  echo "zsh -n: $tmpl"
  SMOKE=1 chezmoi --source . --config "$tmp_cfg" \
    --refresh-externals=never execute-template --file -- "$tmpl" \
    | zsh -n
done
