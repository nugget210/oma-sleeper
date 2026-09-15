#!/usr/bin/env bash
set -euo pipefail

# Sleeper reports two weeks in its NFL state. "week" is the round its matchup
# page has moved on to; "display_week" lags behind so the app can still show the
# finished round's scores. Reading display_week left this panel a round behind
# the matchup the user was looking at, so both the schema and the extraction
# below must keep preferring "week".
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_dir/bin/sleeper-matchup"

# The jq program is lifted from the shipped script rather than restated here.
selector="$(sed -n "s/.*remote_week=\"\$(jq -er '\(.*\)' \"\$state_file\".*/\1/p" "$helper")"
[[ -n "$selector" ]] || { echo "could not extract the week selector" >&2; exit 1; }

schema_source="$(awk "/^readonly state_schema='/,/'\$/" "$helper")"
[[ -n "$schema_source" ]] || { echo "could not extract the state schema" >&2; exit 1; }
eval "$schema_source"

week_of() { jq -er "$selector" 2>/dev/null; }

check() {
  local label="$1" payload="$2" expected="$3" actual
  actual="$(week_of <<<"$payload" || echo ERROR)"
  [[ "$actual" == "$expected" ]] || { echo "FAIL  $label (expected $expected, got $actual)" >&2; exit 1; }
  echo "PASS  $label"
}

# The live case that prompted this: week has rolled over, display_week has not.
check "a rolled-over round follows week, not display_week" \
  '{"week":2,"display_week":1}' 2
check "an unstarted rollover still reports the current round" \
  '{"week":1,"display_week":1}' 1
check "display_week is used only when week is absent" \
  '{"display_week":5}' 5
check "a numeric string week is accepted" \
  '{"week":"3"}' 3
check "a state with no week at all is an error" \
  '{"season":"2026"}' ERROR

schema_check() {
  local label="$1" payload="$2" expected="$3" actual=pass
  jq -e "$state_schema" <<<"$payload" >/dev/null 2>&1 || actual=fail
  [[ "$actual" == "$expected" ]] || { echo "FAIL  $label (expected $expected, got $actual)" >&2; exit 1; }
  echo "PASS  $label"
}

# The schema must validate the same field the selector reads, or a state with a
# valid week and an out-of-range display_week would be rejected before use.
schema_check "the schema validates the week it will actually read" \
  '{"week":2,"display_week":1}' pass
schema_check "the schema rejects an out-of-range week" \
  '{"week":99,"display_week":1}' fail
schema_check "the schema accepts a state carrying only display_week" \
  '{"display_week":4}' pass

echo "Week selection tests passed"
