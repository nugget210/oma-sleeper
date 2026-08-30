#!/usr/bin/env bash
set -euo pipefail

plugin_id="oma-sleeper"
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id"

mkdir -p "$target_dir"
for file in BarWidget.qml Panel.qml PlayerRow.qml TeamColumn.qml manifest.json; do
  install -m 0644 "$source_dir/$file" "$target_dir/$file"
done
install -Dm 0755 "$source_dir/bin/sleeper-matchup" "$target_dir/bin/sleeper-matchup"
install -Dm 0644 "$source_dir/lib/sync-state.jq" "$target_dir/lib/sync-state.jq"

omarchy-shell -q shell rescanPlugins
omarchy bar put "$plugin_id" --before omarchy.clock

echo "Installed $plugin_id. Click NFL SETUP in the bar to connect a Sleeper league."
