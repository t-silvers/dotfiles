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
source utils.sh

ghname=
oflag=
while getopts :go: opt; do
	case $opt in
		g) ghname="$OPTARG" ;;
		o) oflag=1 ;;
		?) usage "[-g GITHUB_USERNAME] [-o]" ;;
	esac >&2
done
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

test_connection() {
	info "Testing internet connection."
	ping -c2 wikipedia.org &> /dev/null \
		|| err "Check internet connection."
}

check_github_username "$ghname"
info "Args: GITHUB_USERNAME=$ghname"
test_connection
command -v curl &> /dev/null || err "curl not found"
info "$(type curl)"

info "Running on $(uname -s)"
if [ "$(uname)" = 'Darwin' ]; then
	if ! xcode-select -p &> /dev/null; then
		warn "Xcode Command Line Tools not found"
		info "Installing Xcode Command Line Tools"
		xcode-select --install
	else
		info "Found Xcode Command Line Tools ($(xcode-select -p))"
	fi
fi

(cd "$HOME"
if ! command -v chezmoi &> /dev/null; then
	warn "Chezmoi not found"
	info "Installing Chezmoi and initializing dotfiles"
	# sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply "$ghname"
	sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --one-shot "$ghname"
else
	info "$(type chezmoi)"
	info "Initializing dotfiles"
	# chezmoi init --apply "$ghname"
	chezmoi init --one-shot "$ghname"
fi
)

info "Restarting shell"
exec "$SHELL" -l