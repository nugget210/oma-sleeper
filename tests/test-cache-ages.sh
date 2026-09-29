#!/usr/bin/env bash
set -euo pipefail

# How long each response may be reused is a deliberate choice per endpoint, and
# getting one wrong is invisible: the panel keeps working and quietly shows
# something out of date. The standings did exactly that, drawn from a roster
# response held for an hour, so the ladder showed the previous round for up to
# an hour after the results were in. These ages are pinned so that lengthening
# one has to be a decision rather than an accident.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_dir/bin/sleeper-matchup"

age_of() {
  sed -n "s/.*cache_fetch \"\?$1\"\? \([0-9]\+\) .*/\1/p" "$helper" | head -1
}

check() {
  local label="$1" name="$2" expected="$3" actual
  actual="$(age_of "$name")"
  [[ "$actual" == "$expected" ]] \
    || { echo "FAIL  $label ($name is ${actual:-unset}s, expected ${expected}s)" >&2; exit 1; }
  echo "PASS  $label"
}

# Carries the season record behind the standings, which turns over when a round
# is finalised. Short, because that moment is unpredictable and is exactly when
# the ladder gets looked at.
check "rosters are re-read often enough for the standings" \
  "rosters-\$league_id" 300

# The round in play, so the panel follows Sleeper within a few minutes.
check "the NFL state is re-read often" "nfl-state" 300

# Backs the scoring breakdown, which has to reconcile against live points.
check "the weekly box score tracks the live cycle" "stats-\$season-\$week" 30

# Scoring rules and display names change almost never.
check "league settings are held for an hour" "league-\$league_id" 3600
check "league users are held for an hour" "users-\$league_id" 3600

# Only feeds a season average, and is far larger than the weekly box score.
check "season totals are held for hours" "stats-season-\$season" 21600

# Sleeper asks that the full player map be fetched sparingly.
check "the player map is held for a day" "players" 86400

# Nothing may be held longer than an hour without a reason recorded above.
while read -r name age; do
  case "$name" in
    "stats-season-\$season"|players|"league-\$league_id"|"users-\$league_id") continue ;;
  esac
  (( age <= 3600 )) || { echo "FAIL  $name is held for ${age}s with no stated reason" >&2; exit 1; }
done < <(sed -n 's/.*cache_fetch "\?\([A-Za-z0-9$_{}\\-]*\)"\? \([0-9]\+\) .*/\1 \2/p' "$helper")
echo "PASS  no endpoint is held longer than an hour without a reason"

echo "Cache age tests passed"
