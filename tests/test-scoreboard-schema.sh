#!/usr/bin/env bash
set -euo pipefail

# ESPN stamps kickoff times without seconds ("2026-09-10T00:20Z"). The schema
# once required jq's stricter fromdateiso8601 form, so every real scoreboard was
# rejected and every player's game status silently fell back to "idle".
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
schema_source="$(awk "/^readonly scoreboard_schema='/,/'\$/" "$repo_dir/bin/sleeper-matchup")"
[[ -n "$schema_source" ]] || { echo "scoreboard schema could not be extracted" >&2; exit 1; }
eval "$schema_source"

event() {
  printf '{"events":[{"date":%s,"season":{"type":2,"year":2026},"week":{"number":%s},"competitions":[{"competitors":[{"team":{"abbreviation":"SEA"}},{"team":{"abbreviation":"NE"}}],"status":{"period":1,"clock":361,"displayClock":"6:01","type":{"state":"in"}}}]}]}' "$1" "${2:-1}"
}

# An event carries the round it belongs to. The scoreboard window spans more
# than one round, and the payload matches a team to its game by that number, so
# an event without it cannot be used.
no_week() {
  printf '{"events":[{"date":"2026-09-10T00:20Z","season":{"type":2,"year":2026},"competitions":[{"competitors":[{"team":{"abbreviation":"SEA"}}],"status":{"period":1,"clock":361,"displayClock":"6:01","type":{"state":"in"}}}]}]}'
}

check() {
  local label="$1" payload="$2" expected="$3" actual=pass
  jq -e "$scoreboard_schema" <<<"$payload" >/dev/null 2>&1 || actual=fail
  [[ "$actual" == "$expected" ]] || { echo "FAIL  $label (expected $expected, got $actual)" >&2; exit 1; }
  echo "PASS  $label"
}

check "minute-precision kickoff is accepted" "$(event '"2026-09-10T00:20Z"')" pass
check "second-precision kickoff is accepted" "$(event '"2026-09-10T00:20:00Z"')" pass
check "empty scoreboard is accepted" '{"events":[]}' pass
check "unparseable kickoff is rejected" "$(event '"not-a-date"')" fail
check "non-string kickoff is rejected" "$(event '12345')" fail
check "a round number is accepted" "$(event '"2026-09-10T00:20Z"' 2)" pass
check "an event without a round number is rejected" "$(no_week)" fail

# ESPN withdrew date-range support, answering 400 to every "dates=from-to"
# request. That failure is silent: the fetch falls back to an empty scoreboard,
# every player reports no game, and the panel quietly loses live detection. The
# round is asked for by number instead, and nothing may reintroduce a range.
grep -q 'week=$week&seasontype=2&year=$season' "$repo_dir/bin/sleeper-matchup" \
  || { echo "FAIL  the scoreboard must be requested by round number" >&2; exit 1; }
echo "PASS  the scoreboard is requested by round number"

grep -qE '^[^#]*scoreboard\?[^"]*dates=' "$repo_dir/bin/sleeper-matchup" \
  && { echo "FAIL  a scoreboard date range would be rejected by ESPN" >&2; exit 1; }
echo "PASS  no scoreboard date range is requested"

# One round must not be served the cache of another.
grep -q 'refresh_cache_or_default "scoreboard-$season-$week"' "$repo_dir/bin/sleeper-matchup" \
  || { echo "FAIL  the scoreboard cache key must carry season and round" >&2; exit 1; }
echo "PASS  the scoreboard cache key carries the round"

echo "Scoreboard schema tests passed"
