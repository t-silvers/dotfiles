#!/usr/bin/env bats

load helpers

@test "bump-version.sh bumps minor, patch, and major versions with trailing newline" {
    local vfile="$FIXTURE/VERSION"
    printf '0.0.0\n' > "$vfile"

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" --read "$vfile"
    [ "$status" -eq 0 ]
    [ "$output" = "0.0.0" ]

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" --read --nonzero "$vfile"
    [ "$status" -ne 0 ]
    [[ "$output" == *'0.0.0'* ]]

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" --next minor "$vfile"
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
    [ "$(cat "$vfile")" = "0.0.0" ]

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" minor "$vfile"
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]
    [ "$(cat "$vfile")" = "0.1.0" ]
    [ "$(tail -c 1 "$vfile" | wc -l | tr -d ' ')" -eq 1 ]

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" --read --nonzero "$vfile"
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.0" ]

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" patch "$vfile"
    [ "$status" -eq 0 ]
    [ "$output" = "0.1.1" ]
    [ "$(cat "$vfile")" = "0.1.1" ]

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" major "$vfile"
    [ "$status" -eq 0 ]
    [ "$output" = "1.0.0" ]
    [ "$(cat "$vfile")" = "1.0.0" ]
}

@test "bump-version.sh rejects invalid parts and malformed or missing VERSION without mutation" {
    local vfile="$FIXTURE/VERSION"

    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" --read "$FIXTURE/missing-VERSION"
    [ "$status" -ne 0 ]
    [[ "$output" == *'not found'* ]]

    printf '0.2.3\n' > "$vfile"
    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" alpha "$vfile"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Invalid version part'* ]]
    [ "$(cat "$vfile")" = "0.2.3" ]

    for bad in 'v1.0.0' '01.0.0' '1.0' '1.0.0-rc1' '' '1.0.0 '; do
        printf '%s\n' "$bad" > "$vfile"
        run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" minor "$vfile"
        [ "$status" -ne 0 ]
        [ "$(cat "$vfile")" = "$bad" ]
    done

    printf '1.0.0\n2.0.0\n' > "$vfile"
    run "$DOTFILES_ROOT/.github/scripts/bump-version.sh" patch "$vfile"
    [ "$status" -ne 0 ]
    [ "$(cat "$vfile")" = "$(printf '1.0.0\n2.0.0')" ]
}

@test "chezmoi managed excludes root VERSION and .github/scripts/*" {
    run "$REAL_CHEZMOI" --config "$FIXTURE/config.toml" \
        --source "$DOTFILES_ROOT" --refresh-externals=never managed
    [ "$status" -eq 0 ]
    ! printf '%s\n' "$output" | grep -Eq '(^|/)VERSION$|\.github/'
}

init_fixture_repo() {
    local repo="$1"
    local remote="$2"
    git init --bare -q --initial-branch=main "$remote"
    git init -q --initial-branch=main "$repo"
    git -C "$repo" config user.name "Fixture User"
    git -C "$repo" config user.email "fixture@example.invalid"
    git -C "$repo" remote add origin "$remote"
    printf '0.0.0\n' > "$repo/VERSION"
    printf 'initial\n' > "$repo/README.md"
    git -C "$repo" add VERSION README.md
    git -C "$repo" commit -qm "Initial commit"
    git -C "$repo" push -q -u origin main
}

@test "watch-ci.sh polls until run appears, watches to completion, and supports explicit ref" {
    local repo="$FIXTURE/repo"
    local remote="$FIXTURE/origin.git"
    init_fixture_repo "$repo" "$remote"
    local first_sha
    first_sha="$(git -C "$repo" rev-parse HEAD)"
    printf 'second\n' >> "$repo/README.md"
    git -C "$repo" commit -qam "Second commit"
    local head_sha
    head_sha="$(git -C "$repo" rev-parse HEAD)"

    printf '0\n' > "$FIXTURE/poll_count"
    stub gh <<'EOF'
printf 'gh %s\n' "$*" >> "$CALLS"
case "$1 $2" in
    'run list')
        count=$(( $(cat "$FIXTURE/poll_count") + 1 ))
        printf '%s\n' "$count" > "$FIXTURE/poll_count"
        if [ "$count" -ge 2 ]; then
            printf '424242\n'
        fi
        ;;
    'run watch')
        exit 0
        ;;
    *)
        exit 99
        ;;
esac
EOF

    run bash -c 'cd "$1" && WATCH_CI_ATTEMPTS=3 WATCH_CI_POLL_SECONDS=0 WATCH_CI_INTERVAL=5 "$2"' \
        -- "$repo" "$DOTFILES_ROOT/.github/scripts/watch-ci.sh"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^gh run list --commit '"$head_sha"' --workflow go-task-ci.yml ' "$CALLS")" -eq 2 ]
    grep -q '^gh run watch 424242 --exit-status --compact --interval 5$' "$CALLS"

    : > "$CALLS"
    printf '1\n' > "$FIXTURE/poll_count"
    run bash -c 'cd "$1" && WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 "$2" HEAD~1' \
        -- "$repo" "$DOTFILES_ROOT/.github/scripts/watch-ci.sh"
    [ "$status" -eq 0 ]
    grep -q "^gh run list --commit $first_sha --workflow go-task-ci.yml " "$CALLS"
}

@test "watch-ci.sh dumps failed logs on CI failure and times out cleanly when no run appears" {
    local repo="$FIXTURE/repo"
    local remote="$FIXTURE/origin.git"
    init_fixture_repo "$repo" "$remote"
    local head_sha
    head_sha="$(git -C "$repo" rev-parse HEAD)"

    stub gh <<'EOF'
printf 'gh %s\n' "$*" >> "$CALLS"
case "$1 $2" in
    'run list')
        printf '999001\n'
        ;;
    'run watch')
        exit 1
        ;;
    'run view')
        printf 'FAILED_STEP_LOG_LINE\n'
        exit 0
        ;;
    *)
        exit 99
        ;;
esac
EOF

    run bash -c 'cd "$1" && WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 "$2"' \
        -- "$repo" "$DOTFILES_ROOT/.github/scripts/watch-ci.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *'FAILED_STEP_LOG_LINE'* ]]
    grep -q '^gh run view 999001 --log-failed$' "$CALLS"

    : > "$CALLS"
    stub gh <<'EOF'
printf 'gh %s\n' "$*" >> "$CALLS"
case "$1 $2" in
    'run list')
        exit 0
        ;;
    *)
        exit 99
        ;;
esac
EOF

    run bash -c 'cd "$1" && WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 "$2"' \
        -- "$repo" "$DOTFILES_ROOT/.github/scripts/watch-ci.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"$head_sha"* ]]
    [ "$(grep -c '^gh run list ' "$CALLS")" -eq 2 ]
}

check_stubs() {
    chezmoi_stub
    stub yamllint <<'EOF'
printf 'yamllint %s\n' "$*" >> "$CALLS"
exit "${YAMLLINT_STATUS:-0}"
EOF
    stub jactionlint <<'EOF'
printf 'jactionlint %s\n' "$*" >> "$CALLS"
exit "${JACTIONLINT_STATUS:-0}"
EOF
    stub shellcheck <<'EOF'
printf 'shellcheck %s\n' "$*" >> "$CALLS"
exit "${SHELLCHECK_STATUS:-0}"
EOF
    stub zsh <<'EOF'
printf 'zsh %s\n' "$*" >> "$CALLS"
exit "${ZSH_STATUS:-0}"
EOF
    stub bats <<'EOF'
printf 'bats %s\n' "$*" >> "$CALLS"
exit "${BATS_STATUS:-0}"
EOF
}

gh_release_stub() {
    stub gh <<'EOF'
printf 'gh %s\n' "$*" >> "$CALLS"
case "$1 $2" in
    'auth status')
        exit "${GH_AUTH_STATUS:-0}"
        ;;
    'run list')
        printf '777001\n'
        ;;
    'run watch')
        exit "${GH_WATCH_STATUS:-0}"
        ;;
    'run view')
        printf 'CI_FAILED_OUTPUT\n'
        exit 0
        ;;
    'release create')
        exit "${GH_RELEASE_STATUS:-0}"
        ;;
    *)
        exit 99
        ;;
esac
EOF
}

task_env_run() {
    local -a envs=()
    while [[ "$#" -gt 0 && "$1" == *=* ]]; do
        envs+=("$1")
        shift
    done
    if [[ "${#envs[@]}" -gt 0 ]]; then
        env "${envs[@]}" "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes "$@"
    else
        "$REAL_TASK" --taskfile "$DOTFILES_ROOT/Taskfile.yml" --yes "$@"
    fi
}

@test "task check runs lint, dry-run, and test in sequence and aborts on lint failure" {
    local repo="$FIXTURE/repo"
    local remote="$FIXTURE/origin.git"
    init_fixture_repo "$repo" "$remote"
    check_stubs

    run task_env_run check "DEV_REPO_DIR=$repo"
    [ "$status" -eq 0 ]
    grep -q '^yamllint -s -c ' "$CALLS"
    grep -q '^jactionlint ' "$CALLS"
    grep -q '^shellcheck ' "$CALLS"
    grep -q "^--source $repo --refresh-externals=never apply --dry-run --verbose --force$" "$CALLS"
    grep -q '^bats --print-output-on-failure tests/unit/' "$CALLS"

    local lint_line dry_line test_line
    lint_line="$(grep -n '^yamllint ' "$CALLS" | head -n 1 | cut -d: -f1)"
    dry_line="$(grep -n 'apply --dry-run --verbose --force$' "$CALLS" | head -n 1 | cut -d: -f1)"
    test_line="$(grep -n '^bats ' "$CALLS" | head -n 1 | cut -d: -f1)"
    [ "$lint_line" -lt "$dry_line" ]
    [ "$dry_line" -lt "$test_line" ]

    : > "$CALLS"
    run task_env_run YAMLLINT_STATUS=1 check "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    grep -q '^yamllint -s -c ' "$CALLS"
    ! grep -q 'apply --dry-run' "$CALLS"
    ! grep -q '^bats ' "$CALLS"

    # task test forwards CLI_ARGS when provided
    : > "$CALLS"
    run task_env_run test "DEV_REPO_DIR=$repo" -- tests/unit/release.bats
    [ "$status" -eq 0 ]
    grep -q '^bats --print-output-on-failure tests/unit/release.bats$' "$CALLS"

    # Missing DEV_REPO_DIR must fail without auto-creating directory on disk
    local missing_dir="$FIXTURE/never-auto-created"
    run task_env_run lint "DEV_REPO_DIR=$missing_dir"
    [ "$status" -ne 0 ]
    [ ! -e "$missing_dir" ]
}

@test "task release supports dirty and clean trees, rejects clean tagged HEAD, and keeps machine sync separate" {
    local repo="$FIXTURE/repo"
    local remote="$FIXTURE/origin.git"
    init_fixture_repo "$repo" "$remote"
    check_stubs
    gh_release_stub

    # 1. Dirty tree release with default PART=minor
    printf 'new change\n' >> "$repo/README.md"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release "DEV_REPO_DIR=$repo"
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/VERSION")" = "0.1.0" ]
    [ "$(git -C "$repo" log -1 --pretty=%s)" = "Release v0.1.0" ]
    [ -z "$(git -C "$repo" status --porcelain)" ]
    [ "$(git -C "$repo" rev-parse v0.1.0^{commit})" = "$(git -C "$repo" rev-parse HEAD)" ]
    [ "$(git -C "$remote" rev-parse refs/tags/v0.1.0^{commit})" = "$(git -C "$repo" rev-parse HEAD)" ]
    grep -q '^gh release create v0.1.0 --verify-tag --generate-notes$' "$CALLS"
    ! grep -Eq '^(update|apply)$' "$CALLS"

    # 2. Clean tree at latest tag must fail before checks or bumping
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'nothing to release'* ]]
    [ "$(cat "$repo/VERSION")" = "0.1.0" ]
    ! grep -q '^yamllint ' "$CALLS"
    ! grep -q '^gh ' "$CALLS"

    # 3. Clean tree with unreleased commit releases cleanly with PART=patch and CLI_ARGS
    printf 'feature commit\n' >> "$repo/README.md"
    git -C "$repo" commit -qam "Add feature"
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release PART=patch "DEV_REPO_DIR=$repo" -- --draft
    [ "$status" -eq 0 ]
    [ "$(cat "$repo/VERSION")" = "0.1.1" ]
    [ "$(git -C "$repo" log -1 --pretty=%s)" = "Release v0.1.1" ]
    [ "$(git -C "$remote" rev-parse refs/tags/v0.1.1^{commit})" = "$(git -C "$repo" rev-parse HEAD)" ]
    grep -q '^gh release create v0.1.1 --verify-tag --generate-notes --draft$' "$CALLS"
    ! grep '^gh run list ' "$CALLS" | grep -q -- '--draft'
    ! grep '^bats ' "$CALLS" | grep -q -- '--draft'
}

@test "task release preserves VERSION on test:ci/auth/tag failure and blocks invalid PART, non-main, or detached HEAD even under --force" {
    local repo="$FIXTURE/repo"
    local remote="$FIXTURE/origin.git"
    init_fixture_repo "$repo" "$remote"
    check_stubs
    gh_release_stub

    local before_sha
    before_sha="$(git -C "$repo" rev-parse HEAD)"
    printf 'dirty edit\n' >> "$repo/README.md"

    # Invalid PART rejected by native requires.vars.enum even under --force
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        --force release PART=alpha "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'alpha'* ]]
    [ "$(cat "$repo/VERSION")" = "0.0.0" ]
    ! grep -q '^bats ' "$CALLS"

    # Unauthenticated gh stops before test:ci or bumping
    : > "$CALLS"
    run task_env_run GH_AUTH_STATUS=1 WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'not authenticated'* ]]
    [ "$(cat "$repo/VERSION")" = "0.0.0" ]
    ! grep -q '^bats ' "$CALLS"

    # Remote tag collision for next version stops before bumping or committing
    local other_clone="$FIXTURE/other"
    git clone -q "$remote" "$other_clone"
    git -C "$other_clone" config user.name "Other"
    git -C "$other_clone" config user.email "other@example.invalid"
    git -C "$other_clone" tag -a v0.1.0 -m "Pre-existing remote tag"
    git -C "$other_clone" push -q origin refs/tags/v0.1.0
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'already exists on origin'* ]]
    [ "$(cat "$repo/VERSION")" = "0.0.0" ]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before_sha" ]
    git -C "$remote" tag -d v0.1.0 >/dev/null

    # test:ci failure leaves VERSION untouched
    : > "$CALLS"
    run task_env_run BATS_STATUS=1 WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    grep -q '^bats ' "$CALLS"
    [ "$(cat "$repo/VERSION")" = "0.0.0" ]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before_sha" ]
    [ -z "$(git -C "$repo" tag -l)" ]
    ! grep -q '^gh release create ' "$CALLS"

    # Non-main branch rejected even under --force
    git -C "$repo" checkout -qb feat/other
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        --force release "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'branch main'* ]]
    [ "$(cat "$repo/VERSION")" = "0.0.0" ]
    ! grep -q '^gh ' "$CALLS"

    # Detached HEAD rejected even under --force
    git -C "$repo" checkout -q --detach HEAD
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        --force release "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'branch main'* ]]
    [ "$(cat "$repo/VERSION")" = "0.0.0" ]
    ! grep -q '^gh ' "$CALLS"
}

@test "task release:publish stops before tagging on CI failure, retries after fix commit, and validates guards even under --force" {
    local repo="$FIXTURE/repo"
    local remote="$FIXTURE/origin.git"
    init_fixture_repo "$repo" "$remote"
    check_stubs
    gh_release_stub

    # Guard: unbumped VERSION=0.0.0 rejected even under --force
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        --force release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'0.0.0'* ]]
    ! grep -q '^gh release create ' "$CALLS"

    # Guard: malformed committed VERSION rejected before pushing
    printf 'v0.1.0\n' > "$repo/VERSION"
    git -C "$repo" commit -qam "Malformed version"
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Invalid SemVer'* ]]
    ! grep -q '^gh ' "$CALLS"

    # Guard: dirty tree rejected even under --force
    printf '0.1.0\n' > "$repo/VERSION"
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        --force release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'uncommitted changes'* ]]
    ! grep -q '^gh ' "$CALLS"

    # Commit bumped VERSION, verify off-main and detached HEAD rejected
    git -C "$repo" commit -qam "Release v0.1.0"
    git -C "$repo" checkout -qb feat/publish-check
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'branch main'* ]]
    ! grep -q '^gh ' "$CALLS"
    git -C "$repo" checkout -q --detach HEAD
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'branch main'* ]]
    git -C "$repo" checkout -q main
    git -C "$repo" branch -D feat/publish-check >/dev/null

    # Fail CI watch -> no tag, no release
    : > "$CALLS"
    run task_env_run GH_WATCH_STATUS=1 WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'CI_FAILED_OUTPUT'* ]]
    [ -z "$(git -C "$repo" tag -l v0.1.0)" ]
    [ -z "$(git -C "$remote" tag -l v0.1.0)" ]
    ! grep -q '^gh release create ' "$CALLS"

    # Commit fix on main without re-bumping VERSION, then retry release:publish
    printf 'ci fix\n' >> "$repo/README.md"
    git -C "$repo" commit -qam "Fix CI"
    local fixed_sha
    fixed_sha="$(git -C "$repo" rev-parse HEAD)"
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release:publish "DEV_REPO_DIR=$repo" -- --draft
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" rev-parse v0.1.0^{commit})" = "$fixed_sha" ]
    [ "$(git -C "$remote" rev-parse refs/tags/v0.1.0^{commit})" = "$fixed_sha" ]
    grep -q '^gh release create v0.1.0 --verify-tag --generate-notes --draft$' "$CALLS"
    ! grep '^gh run list ' "$CALLS" | grep -q -- '--draft'

    # Idempotent retry when local & remote tag already point to HEAD
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -eq 0 ]
    grep -q '^gh release create v0.1.0 --verify-tag --generate-notes$' "$CALLS"

    # Guard: conflicting existing tag on another commit is rejected before push even under --force
    printf 'later commit\n' >> "$repo/README.md"
    git -C "$repo" commit -qam "Later commit"
    : > "$CALLS"
    run task_env_run WATCH_CI_ATTEMPTS=2 WATCH_CI_POLL_SECONDS=0 \
        --force release:publish "DEV_REPO_DIR=$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *'already exists'* ]]
    ! grep -q '^gh release create ' "$CALLS"
    [ "$(git -C "$remote" rev-parse refs/heads/main)" = "$fixed_sha" ]
}
