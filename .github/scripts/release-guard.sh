#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat >&2 <<'EOF'
Usage:
  release-guard.sh prepare <REPO_DIR> <BRANCH> <PART>
  release-guard.sh publish <REPO_DIR> <BRANCH>
EOF
  exit 1
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

check_repo_and_branch() {
  local repo_dir="$1"
  local expected_branch="$2"

  if [[ ! -d "$repo_dir" ]]; then
    die "Repository directory does not exist: $repo_dir"
  fi
  if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
    die "Not a git repository: $repo_dir"
  fi

  local branch
  branch="$(git -C "$repo_dir" symbolic-ref --short -q HEAD || true)"
  if [[ "$branch" != "$expected_branch" ]]; then
    die "Releases must run from branch $expected_branch (not detached HEAD or another branch)."
  fi
  if ! git -C "$repo_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    die "Repository has no commits on branch $expected_branch."
  fi
}

check_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    die "GitHub CLI (gh) is required to publish releases."
  fi
  if ! gh auth status >/dev/null 2>&1; then
    die "GitHub CLI (gh) is not authenticated; run 'gh auth login' first."
  fi
}

remote_tag_commit() {
  local repo_dir="$1"
  local tag="$2"
  local lines
  lines="$(git -C "$repo_dir" ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")"
  if [[ -z "$lines" ]]; then
    return 0
  fi
  printf '%s\n' "$lines" | awk -v t="refs/tags/$tag" '
    $2 == t "^{}" { peeled = $1 }
    $2 == t { direct = $1 }
    END { print (peeled != "" ? peeled : direct) }
  '
}

if [[ "$#" -lt 1 ]]; then
  usage
fi

mode="$1"
shift

case "$mode" in
  prepare)
    if [[ "$#" -ne 3 ]]; then
      usage
    fi
    repo_dir="$1"
    expected_branch="$2"
    part="$3"

    check_repo_and_branch "$repo_dir" "$expected_branch"

    next_ver="$("$script_dir/bump-version.sh" --next "$part" "$repo_dir/VERSION")"
    next_tag="v$next_ver"

    if [[ -z "$(git -C "$repo_dir" status --porcelain)" ]]; then
      latest_tag="$(
        git -C "$repo_dir" describe --tags --abbrev=0 \
          --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true
      )"
      if [[ -n "$latest_tag" ]]; then
        count="$(git -C "$repo_dir" rev-list --count "${latest_tag}..HEAD")"
        if [[ "$count" -eq 0 ]]; then
          die "Working tree is clean and no commits exist since $latest_tag; nothing to release."
        fi
      fi
    fi

    if git -C "$repo_dir" rev-parse -q --verify "refs/tags/$next_tag" >/dev/null; then
      die "Next release tag $next_tag already exists locally."
    fi

    check_gh

    remote_sha="$(remote_tag_commit "$repo_dir" "$next_tag")"
    if [[ -n "$remote_sha" ]]; then
      die "Next release tag $next_tag already exists on origin ($remote_sha)."
    fi
    ;;

  publish)
    if [[ "$#" -ne 2 ]]; then
      usage
    fi
    repo_dir="$1"
    expected_branch="$2"

    check_repo_and_branch "$repo_dir" "$expected_branch"

    if [[ -n "$(git -C "$repo_dir" status --porcelain)" ]]; then
      die "Working tree has uncommitted changes; commit them before running 'task release:publish'."
    fi

    ver="$("$script_dir/bump-version.sh" --read --nonzero "$repo_dir/VERSION")"
    tag="v$ver"
    head_sha="$(git -C "$repo_dir" rev-parse HEAD)"

    if git -C "$repo_dir" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      tag_sha="$(git -C "$repo_dir" rev-parse "refs/tags/$tag^{commit}")"
      if [[ "$tag_sha" != "$head_sha" ]]; then
        die "Tag $tag already exists locally on a different commit ($tag_sha != $head_sha)."
      fi
    fi

    check_gh

    remote_sha="$(remote_tag_commit "$repo_dir" "$tag")"
    if [[ -n "$remote_sha" && "$remote_sha" != "$head_sha" ]]; then
      die "Tag $tag already exists on origin on a different commit ($remote_sha != $head_sha)."
    fi
    ;;

  *)
    usage
    ;;
esac
