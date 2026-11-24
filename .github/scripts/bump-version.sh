#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  bump-version.sh --read [--nonzero] [FILE]
  bump-version.sh --next <major|minor|patch> [FILE]
  bump-version.sh <major|minor|patch> [FILE]
EOF
  exit 1
}

compute_next() {
  local part="$1"
  case "$part" in
    major)
      printf '%s.0.0\n' "$((10#$MAJOR + 1))"
      ;;
    minor)
      printf '%s.%s.0\n' "$MAJOR" "$((10#$MINOR + 1))"
      ;;
    patch)
      printf '%s.%s.%s\n' "$MAJOR" "$MINOR" "$((10#$PATCH + 1))"
      ;;
    *)
      printf 'Invalid version part: %s (expected major, minor, or patch)\n' "$part" >&2
      exit 1
      ;;
  esac
}

read_version() {
  local file="$1"
  local nonzero="$2"

  if [[ ! -f "$file" || ! -r "$file" ]]; then
    printf 'VERSION file not found or unreadable: %s\n' "$file" >&2
    exit 1
  fi

  local line_count=0
  local line=""
  local first_line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_count=$((line_count + 1))
    if [[ "$line_count" -eq 1 ]]; then
      first_line="$line"
    fi
  done < "$file"

  if [[ "$line_count" -ne 1 ]]; then
    printf 'Invalid VERSION file %s: expected a single MAJOR.MINOR.PATCH line\n' "$file" >&2
    exit 1
  fi

  local semver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  if [[ ! "$first_line" =~ $semver_re ]]; then
    printf 'Invalid SemVer in %s: %q (expected MAJOR.MINOR.PATCH)\n' "$file" "$first_line" >&2
    exit 1
  fi

  if [[ "$nonzero" -eq 1 && "$first_line" == "0.0.0" ]]; then
    printf 'VERSION in %s is 0.0.0; bump version before publishing\n' "$file" >&2
    exit 1
  fi

  MAJOR="${BASH_REMATCH[1]}"
  MINOR="${BASH_REMATCH[2]}"
  PATCH="${BASH_REMATCH[3]}"
  CURRENT_VERSION="$first_line"
}

if [[ "$#" -lt 1 ]]; then
  usage
fi

mode="$1"
shift

case "$mode" in
  --read)
    nonzero=0
    if [[ "${1:-}" == "--nonzero" ]]; then
      nonzero=1
      shift
    fi
    if [[ "$#" -gt 1 ]]; then
      usage
    fi
    file="${1:-VERSION}"
    read_version "$file" "$nonzero"
    printf '%s\n' "$CURRENT_VERSION"
    ;;
  --next)
    if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
      usage
    fi
    part="$1"
    file="${2:-VERSION}"
    read_version "$file" 0
    compute_next "$part"
    ;;
  major|minor|patch)
    if [[ "$#" -gt 1 ]]; then
      usage
    fi
    file="${1:-VERSION}"
    read_version "$file" 0
    next_version="$(compute_next "$mode")"
    dir="$(dirname -- "$file")"
    tmp="$(mktemp "$dir/.VERSION.XXXXXX")"
    trap 'rm -f -- "$tmp"' EXIT
    printf '%s\n' "$next_version" > "$tmp"
    mv -f -- "$tmp" "$file"
    trap - EXIT
    printf '%s\n' "$next_version"
    ;;
  *)
    printf 'Invalid version part: %s (expected major, minor, patch, or --read)\n' "$mode" >&2
    exit 1
    ;;
esac
