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
  lib/secure-helper.py
  lib/sync-state.jq
  tests/test-qml-safety.sh
  tests/test-resource-safety.sh
)

for file in "${required_files[@]}"; do
  test -f "$repo_dir/$file"
done

test -x "$repo_dir/bin/sleeper-matchup"
test ! -e "$repo_dir/install.sh"
jq -e '.id == "nugget210.oma-sleeper" and .entryPoints.barWidget == "BarWidget.qml"' "$repo_dir/manifest.json" >/dev/null
grep -q 'setting("leagueId", "")' "$repo_dir/Panel.qml"
grep -q 'setting("rosterId", 0)' "$repo_dir/Panel.qml"
grep -q 'setting("shortName", "")' "$repo_dir/Panel.qml"
grep -q '`curl`' "$repo_dir/README.md"
grep -q '`jq`' "$repo_dir/README.md"
grep -q 'Python 3' "$repo_dir/README.md"
grep -q 'manual setup' "$repo_dir/README.md"

echo "Plugin layout test passed"
