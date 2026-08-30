#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
classifier="$repo_dir/lib/sync-state.jq"
now_ms=1788105600000

classify() {
  jq -r --argjson now "$now_ms" -f "$classifier"
}

live='{"events":[{"date":"2026-08-30T08:00:00Z","status":{"type":{"state":"in"}}}]}'
pregame='{"events":[{"date":"2026-08-30T17:30:00Z","status":{"type":{"state":"pre"}}}]}'
later='{"events":[{"date":"2026-08-31T17:30:00Z","status":{"type":{"state":"pre"}}}]}'
complete='{"events":[{"date":"2026-08-30T14:00:00Z","status":{"type":{"state":"post"}}}]}'

[[ "$(classify <<<"$live")" == live ]]
[[ "$(classify <<<"$pregame")" == pregame ]]
[[ "$(classify <<<"$later")" == idle ]]
[[ "$(classify <<<"$complete")" == idle ]]
[[ "$(classify <<<'{"events":[]}')" == idle ]]

echo "Adaptive sync-state tests passed"
