#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$CHEZMOI_SOURCE_DIR/../utils.sh"

[ "${SMOKE:=0}" = 1 ] && exit 0

if [ $# -lt 1 ]; then
    usage "username:service1 username:service2..."
fi
info "Args: $*"
info "Running on $(uname -s)"
if [ "$(uname -s)" != "Darwin" ]; then
    warn "Keychain is only available on macOS/Darwin. Exiting."
    exit 0
fi
command -v security &> /dev/null || err "security not found."
info "$(type security)"

keychain_add() {
    info "Adding account '$account' for service '$service' to keychain."
    security add-generic-password -a "$account" -s "$service" -w
}

keychain_has() {
    security find-generic-password -a "$account" -s "$service" &> /dev/null \
        || return "$?"
    info "Found account '$account' with service '$service' in keychain. Doing nothing."
}

for pair in "$@"; do
    case "$pair" in
        *:*) ;;
        *) usage "username:service1 username:service2..." ;;
    esac
    account="${pair%%:*}"
    service="${pair#*:}"
    if [ -z "$account" ] || [ -z "$service" ]; then
        usage "username:service1 username:service2..."
    fi
    keychain_has && continue
    keychain_add
done
