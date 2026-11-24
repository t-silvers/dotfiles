#!/usr/bin/env bash
#
# Install chezmoi and your dotfiles on a new machine
#
# Adapted from
# `chezmoi generate install-init-shell.sh $GITHUB_USERNAME`
#
# On using --apply vs. --one-shot:
# https://www.chezmoi.io/user-guide/daily-operations/#install-chezmoi-and-your-dotfiles-on-a-new-machine-with-a-single-command
#
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

ghname=
oflag=
while getopts :g:o opt; do
	case $opt in
		g) ghname="$OPTARG" ;;
		o) oflag=1 ;;
		:|?) usage "[-g GITHUB_USERNAME] [-o]" ;;
	esac >&2
done
shift "$((OPTIND - 1))"
if [ "$#" -ne 0 ]; then
	usage "[-g GITHUB_USERNAME] [-o]"
fi
if [ ! "$ghname" ]; then
	usage "[-g GITHUB_USERNAME]"
fi
if [ "$oflag" ]; then
	info "Using chezmoi init --one-shot"
fi

check_github_username() {
    local name="$1"
    http_request_succeeded \
        "https://api.github.com/users/$name" \
        "GitHub user $name not found"
}

command -v curl &> /dev/null || err "curl not found"
info "$(type curl)"
check_github_username "$ghname"
info "Args: GITHUB_USERNAME=$ghname"

info "Running on $(uname -s)"
if [ "$(uname)" = 'Darwin' ]; then
	if ! xcode-select -p &> /dev/null; then
		warn "Xcode Command Line Tools not found"
		info "Starting Xcode Command Line Tools installer"
		xcode-select --install || true
		err "Complete Xcode Command Line Tools installation, then re-run install.sh."
	else
		info "Found Xcode Command Line Tools ($(xcode-select -p))"
	fi
fi

(cd "$HOME"
if ! command -v chezmoi &> /dev/null; then
	warn "Chezmoi not found"
	info "Installing Chezmoi to $HOME/.local/bin and initializing dotfiles"
	mkdir -p "$HOME/.local/bin"
	if [ "$oflag" ]; then
		sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin" init --one-shot "$ghname"
	else
		sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply "$ghname"
	fi
else
	info "$(type chezmoi)"
	info "Initializing dotfiles"
	if [ "$oflag" ]; then
		chezmoi init --one-shot "$ghname"
	else
		chezmoi init --apply "$ghname"
	fi
fi
)

info "Restarting shell"
exec "${SHELL:-/bin/sh}" -l
