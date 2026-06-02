#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$CHEZMOI_SOURCE_DIR/../utils.sh"

SNAPSHOT_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/snapshots/dotfiles/"
info "Number of snapshots: $(
  find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d |
    awk 'END { print NR }'
)"
SNAPSHOT_DIR="$SNAPSHOT_ROOT"
SNAPSHOT_DIR+="$(date +%Y-%m-%d/%H-%M-%S)"
SNAPSHOT_MANIFEST_FILE=managed.txt
mkdir -p "$SNAPSHOT_DIR"
info "Backing up dotfiles to $SNAPSHOT_DIR"

save_snapshot() {
    if [ ! -f "$abspath" ]; then
        warn "File $relpath is managed by chezmoi, \
              but does not exist ($abspath)"
        return 0
    fi
    mkdir -p "$(dirname "$relpath")"
    if [ -w "$abspath" ]; then
        cp "$abspath" "$relpath"
    else
        if ! have_sudo; then
            warn "Cannot back up $abspath (need sudo)"
            return 0
        fi
        sudo -p "Enter password to copy $relpath: " \
            cp "$abspath" "$relpath"
    fi
    info "Back-up of $relpath created at $(realpath "$relpath")"
}

make_backup() {
    chezmoi managed -i files > "$SNAPSHOT_MANIFEST_FILE"
    info "Dotfile snapshot manifest: \
          $(realpath "$SNAPSHOT_MANIFEST_FILE")"

    while IFS= read -r relpath <&3 && 
          IFS= read -r abspath <&4
    do
        save_snapshot
    done 3< <(chezmoi managed -i files) \
         4< <(chezmoi managed -i files -p absolute)

    echo "/etc/krb5.conf" >> "$SNAPSHOT_MANIFEST_FILE"
    abspath=/etc/krb5.conf relpath=etc/krb5.conf save_snapshot
}

( cd "$SNAPSHOT_DIR" && make_backup )
