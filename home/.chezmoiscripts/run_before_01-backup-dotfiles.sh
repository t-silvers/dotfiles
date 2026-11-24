#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$CHEZMOI_SOURCE_DIR/../utils.sh"

CHEZMOI_BIN="${CHEZMOI_EXECUTABLE:-chezmoi}"
DEST_DIR="${CHEZMOI_DEST_DIR:-$HOME}"
SNAPSHOT_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/snapshots/dotfiles/"
mkdir -p "$SNAPSHOT_ROOT"
info "Number of snapshots: $(
  find "$SNAPSHOT_ROOT" -mindepth 2 -maxdepth 2 -type d |
    awk 'END { print NR }'
)"
SNAPSHOT_DIR="${SNAPSHOT_ROOT}$(date +%Y-%m-%d/%H-%M-%S)"
SNAPSHOT_MANIFEST_FILE=managed.txt
mkdir -p "$SNAPSHOT_DIR"
info "Backing up dotfiles to $SNAPSHOT_DIR"

is_excluded_secret() {
    case "$1" in
        .netrc|*/.netrc) return 0 ;;
        *) return 1 ;;
    esac
}

save_snapshot() {
    local relpath="$1"
    local abspath="$2"
    if [ ! -f "$abspath" ]; then
        warn "File $relpath is managed by chezmoi, but does not exist ($abspath)"
        return 0
    fi
    mkdir -p "$(dirname "$relpath")"
    if [ -r "$abspath" ]; then
        cp -p -- "$abspath" "$relpath"
    else
        if ! have_sudo; then
            warn "Cannot back up $abspath (need sudo)"
            return 0
        fi
        sudo -p "Enter password to copy $relpath: " \
            cp -p -- "$abspath" "$relpath"
    fi
    info "Back-up of $relpath created at $(realpath "$relpath")"
}

make_backup() {
    local -a chezmoi_args=(
        --source "$CHEZMOI_SOURCE_DIR"
        --refresh-externals=never
    )
    if [ -n "${CHEZMOI_CONFIG_FILE:-}" ]; then
        chezmoi_args+=(--config "$CHEZMOI_CONFIG_FILE")
    fi

    local managed_files
    managed_files="$(SMOKE=1 "$CHEZMOI_BIN" "${chezmoi_args[@]}" managed -i files)"

    : > "$SNAPSHOT_MANIFEST_FILE"
    while IFS= read -r relpath; do
        [ -n "$relpath" ] || continue
        if is_excluded_secret "$relpath"; then
            info "Skipping secret file $relpath from snapshot backup"
            continue
        fi
        printf '%s\n' "$relpath" >> "$SNAPSHOT_MANIFEST_FILE"
        save_snapshot "$relpath" "$DEST_DIR/$relpath"
    done <<< "$managed_files"

    info "Dotfile snapshot manifest: $(realpath "$SNAPSHOT_MANIFEST_FILE")"

    if [ -f /etc/krb5.conf ]; then
        echo "/etc/krb5.conf" >> "$SNAPSHOT_MANIFEST_FILE"
        save_snapshot "etc/krb5.conf" "/etc/krb5.conf"
    fi
}

( cd "$SNAPSHOT_DIR" && make_backup )
