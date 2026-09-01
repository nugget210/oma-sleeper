#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/home"

cat > "$test_root/bin/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$test_root/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "bar put nugget210.oma-sleeper --before omarchy.clock" ]]
EOF
chmod +x "$test_root/bin/omarchy-shell" "$test_root/bin/omarchy"

HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" PATH="$test_root/bin:$PATH" "$repo_dir/install.sh"

installed="$test_root/home/.config/omarchy/plugins/nugget210.oma-sleeper"
test -x "$installed/bin/sleeper-matchup"
test -f "$installed/lib/sync-state.jq"
jq -e '.id == "nugget210.oma-sleeper" and .entryPoints.barWidget == "BarWidget.qml"' "$installed/manifest.json" >/dev/null
grep -q 'setting("leagueId", "")' "$installed/Panel.qml"
grep -q 'setting("rosterId", 0)' "$installed/Panel.qml"
grep -q 'setting("shortName", "")' "$installed/Panel.qml"

echo "Clean-install test passed"
