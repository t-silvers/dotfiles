#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$CHEZMOI_SOURCE_DIR/../utils.sh"

[ "${SMOKE:=0}" = 1 ] && exit

if [ $# -lt 1 ]; then
    usage "username:service1 username:service2..."
fi
info "Args: $*"
info "Running on $(uname -s)"
if [ ! "$(uname -s)" = "Darwin" ]; then
    warn "Keychain is only available on macOS/Darwin. Exiting."
    exit 0
fi
command -v security &> /dev/null || err "security not found."
info "$(type security)"

keychain_add() {
    info "Adding account '$account' for service '$service' to keychain."
    read -r -s -p "Enter password: " password
    printf "%b" "\n"
    security add-generic-password -a "$account" -s "$service" -w "$password"
}

keychain_has() {
    security find-generic-password -a "$account" -s "$service" &> /dev/null \
        || return "$?"
    info "Found account '$account' with service '$service' in keychain. \
          Doing nothing."
}

while IFS=: read -r account service; do
    keychain_has && continue
    keychain_add
done < <(printf '%s\n' "$@")