#!/usr/bin/env bash
set -euo pipefail

# The ESPN scoreboard window deliberately spans more than one round, so a team
# appears in it several times. Matching only on the team returned the finished
# game from the round before, which made every player of the new round look as
# though they had already played and scored nothing. The definitions below are
# lifted from the shipped payload builder rather than restated here.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_dir/bin/sleeper-matchup"

defs="$(awk '/^  def short_text\(/{f=1} f&&/^  def teamname\(/{exit} f' "$helper")
$(awk '/^  def kickoff_epoch\(/{f=1} f&&/^  def league_points\(/{exit} f' "$helper")"
[[ "$defs" == *"game_status"* && "$defs" == *"short_text"* ]] \
  || { echo "could not extract the game-status definitions" >&2; exit 1; }

# One team, two rounds: a finished game in round 1 and an upcoming one in round 2.
board='{"events":[
  {"season":{"type":2,"year":2026},"week":{"number":1},
   "competitions":[{"competitors":[{"team":{"abbreviation":"NE"}}],
     "status":{"period":4,"clock":0,"displayClock":"0:00","type":{"state":"post"}}}]},
  {"season":{"type":2,"year":2026},"week":{"number":2},
   "competitions":[{"competitors":[{"team":{"abbreviation":"NE"}}],
     "status":{"period":2,"clock":450,"displayClock":"7:30","type":{"state":"in"}}}]},
  {"season":{"type":1,"year":2026},"week":{"number":2},
   "competitions":[{"competitors":[{"team":{"abbreviation":"GB"}}],
     "status":{"period":1,"clock":900,"displayClock":"15:00","type":{"state":"in"}}}]}]}'

status_for() {
  jq -nr --argjson scoreboard "$board" --argjson league '{"season":"2026"}' \
    --argjson week "$1" --arg team "$2" \
    "$defs game_status(\$team) | \"\(.state) \(.period)\""
}

check() {
  local label="$1" actual="$2" expected="$3"
  [[ "$actual" == "$expected" ]] || { echo "FAIL  $label (expected '$expected', got '$actual')" >&2; exit 1; }
  echo "PASS  $label"
}

check "the round on screen selects its own game, not the previous one" \
  "$(status_for 2 NE)" "in 2"
check "an earlier round still resolves to that round's game" \
  "$(status_for 1 NE)" "post 4"
check "a round the team does not appear in reports nothing" \
  "$(status_for 3 NE)" "idle 0"
check "a team absent from the scoreboard reports nothing" \
  "$(status_for 2 SEA)" "idle 0"
# Preseason shares the round numbering, so season type has to be checked too.
check "a preseason game is never matched" \
  "$(status_for 2 GB)" "idle 0"

echo "Game status tests passed"
