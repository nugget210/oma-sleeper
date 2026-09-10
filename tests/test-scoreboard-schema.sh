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
  printf '{"events":[{"date":%s,"season":{"type":2,"year":2026},"competitions":[{"competitors":[{"team":{"abbreviation":"SEA"}},{"team":{"abbreviation":"NE"}}],"status":{"period":1,"clock":361,"displayClock":"6:01","type":{"state":"in"}}}]}]}' "$1"
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

echo "Scoreboard schema tests passed"
