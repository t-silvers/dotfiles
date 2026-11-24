#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 1 ]]; then
  echo "Usage: watch-ci.sh [GIT_REF]" >&2
  exit 1
fi

workflow="${CI_WORKFLOW:-go-task-ci.yml}"
attempts="${WATCH_CI_ATTEMPTS:-30}"
poll_seconds="${WATCH_CI_POLL_SECONDS:-2}"
interval="${WATCH_CI_INTERVAL:-10}"

sha="$(git rev-parse "${1:-HEAD}^{commit}")"
run_id=""

for ((i = 1; i <= attempts; i++)); do
  run_id="$(
    gh run list \
      --commit "$sha" \
      --workflow "$workflow" \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // empty'
  )"
  if [[ -n "$run_id" ]]; then
    break
  fi
  if [[ "$i" -lt "$attempts" && "$poll_seconds" -gt 0 ]]; then
    sleep "$poll_seconds"
  fi
done

if [[ -z "$run_id" ]]; then
  printf 'No GitHub Actions run found for %s (workflow: %s)\n' "$sha" "$workflow" >&2
  exit 1
fi

if ! gh run watch "$run_id" --exit-status --compact --interval "$interval"; then
  gh run view "$run_id" --log-failed || true
  exit 1
fi
