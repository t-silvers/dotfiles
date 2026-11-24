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
    if ! command -v sudo &> /dev/null; then
        warn "sudo not found; user ${USER:-unknown} does not have sudo access"
        return 1
    fi
    if ! sudo -p "Check sudo access. Password: " -v; then
        warn "User ${USER:-unknown} does not have sudo access"
        return 1
    fi
    info "User ${USER:-unknown} has sudo"
}

http_request_succeeded() {
    local code curl_status=0
    local url="$1"
    shift
    # Use --out-null instead of -o if curl >= 8.16
    code="$(curl -s -w '%{response_code}\n' "$url" -o /dev/null)" || curl_status=$?
    if [ "$curl_status" -ne 0 ]; then
        err "$* (curl exit $curl_status)."
    fi
    if [ "$code" != "200" ]; then
        err "$* (HTTP $code)."
    fi
}
