#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  BarWidget.qml
  Panel.qml
  PlayerRow.qml
  TeamColumn.qml
  manifest.json
  bin/sleeper-matchup
  bin/play-alert
  bin/notify-alert
  lib/secure-helper.py
  lib/sync-state.jq
  assets/sounds/ding.wav
  assets/sounds/chime.wav
  assets/sounds/blip.wav
  assets/sounds/lead-up.wav
  assets/sounds/lead-down.wav
  assets/sounds/generate-sounds.py
  tests/alert-logic.js
  tests/test-alert-logic.sh
  tests/test-qml-safety.sh
  tests/test-scoreboard-schema.sh
  tests/test-cache-race.sh
  tests/test-week-selection.sh
  tests/test-game-status.sh
  tests/test-sync-state.sh
  tests/test-resource-safety.sh
)

for file in "${required_files[@]}"; do
  test -f "$repo_dir/$file"
done

test -x "$repo_dir/bin/sleeper-matchup"
test -x "$repo_dir/bin/play-alert"
test -x "$repo_dir/bin/notify-alert"
grep -q 'setting("scoreSound", "ding")' "$repo_dir/Panel.qml"
grep -q 'setting("leadAlert", true)' "$repo_dir/Panel.qml"
grep -q 'setting("notifyAlerts", true)' "$repo_dir/Panel.qml"
grep -q -- '--photo' "$repo_dir/bin/sleeper-matchup"
grep -q 'sleepercdn.com' "$repo_dir/bin/sleeper-matchup"
test ! -e "$repo_dir/install.sh"
jq -e '.id == "nugget210.oma-sleeper" and .entryPoints.barWidget == "BarWidget.qml"' "$repo_dir/manifest.json" >/dev/null
grep -q 'setting("leagueId", "")' "$repo_dir/Panel.qml"
grep -q 'setting("rosterId", 0)' "$repo_dir/Panel.qml"
grep -q 'setting("shortName", "")' "$repo_dir/Panel.qml"
# The marketplace submission checklist requires the README to document the
# external dependencies, the licence, and both install and removal.
grep -q '`curl`' "$repo_dir/README.md"
grep -q '`jq`' "$repo_dir/README.md"
grep -q 'Python 3' "$repo_dir/README.md"
grep -q 'omarchy plugin add' "$repo_dir/README.md"
grep -q 'omarchy plugin remove' "$repo_dir/README.md"
grep -q 'omarchy plugin update' "$repo_dir/README.md"
grep -qi 'MIT' "$repo_dir/README.md"

echo "Plugin layout test passed"
