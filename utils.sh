#!/usr/bin/env bash

log() {
    printf '%s [%s] (%s) %s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${level+$level}" \
    "${0##*/}" \
    "$*" \
    >&2
}
err() { level="ERROR" log "$*"; exit 1; }
info() { level="INFO" log "$*"; }
warn() { level="WARNING" log "$*"; }
usage() { err "usage: ${0##*/} $*"; }

have_sudo() {
    [ "${EUID:-${UID}}" = "0" ] && return 0
    sudo -p "Check sudo access, then reset timestamp. Password: " -v
    sudo -v -n \
        || { warn "User ${USER} does not have sudo access"; return 1; }
    info "User ${USER} has sudo"
    sudo -k
}

http_request_succeeded() {
	local code
    local url="$1"
    shift
    # Use --out-null instead of -o if curl >= 8.16
	code="$(curl -s -w '%{response_code}\n' "$url" -o /dev/null)"
    if [ ! "$code" = "200" ]; then
        err "$* (HTTP $code)."
    fi
}