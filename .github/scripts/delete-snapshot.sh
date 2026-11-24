#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: delete-snapshot.sh [--check] <SNAPSHOT_ROOT> <DATE>" >&2
  exit 1
}

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
  shift
fi

if [[ "$#" -ne 2 ]]; then
  usage
fi

snapshot_root="$1"
snapshot_date="$2"

date_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}(/[0-9]{2}-[0-9]{2}-[0-9]{2})?$'
if [[ ! "$snapshot_date" =~ $date_re ]]; then
  echo "DATE must be YYYY-MM-DD or YYYY-MM-DD/HH-MM-SS." >&2
  exit 1
fi

if [[ ! -d "$snapshot_root" ]]; then
  echo "Snapshot root does not exist: $snapshot_root" >&2
  exit 1
fi

root_real="$(realpath "$snapshot_root")"
if [[ "$root_real" == "/" ]]; then
  echo "Refusing to operate on filesystem root." >&2
  exit 1
fi
target_path="$snapshot_root/$snapshot_date"
if [[ ! -e "$target_path" ]]; then
  echo "Snapshot must be an existing directory inside the snapshot root." >&2
  exit 1
fi

target_real="$(realpath "$target_path")"
if [[ ! -d "$target_real" ]]; then
  echo "Snapshot must be an existing directory inside the snapshot root." >&2
  exit 1
fi

case "$target_real" in
  "$root_real"/*) ;;
  *)
    echo "Snapshot must be an existing directory inside the snapshot root." >&2
    exit 1
    ;;
esac

if [[ "$check_only" -eq 1 ]]; then
  exit 0
fi

rm -rf -- "$target_real"
