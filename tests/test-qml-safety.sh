#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
qml_files=(Panel.qml TeamColumn.qml PlayerRow.qml)

text_items="$(rg -o '\bText\s*\{' "${qml_files[@]/#/$repo_dir/}" | wc -l)"
plain_text_items="$(rg -o 'textFormat:\s*Text\.PlainText' "${qml_files[@]/#/$repo_dir/}" | wc -l)"
[[ "$text_items" -eq "$plain_text_items" ]]

grep -q 'readonly property int maxLabelLength: 24' "$repo_dir/Panel.qml"
grep -q 'maximumLength: root.maxLabelLength' "$repo_dir/Panel.qml"
[[ "$(grep -c 'maximumLength: root.maxLabelLength' "$repo_dir/Panel.qml")" -eq 2 ]]
grep -q 'shortName:root.boundedLabel(label)' "$repo_dir/Panel.qml"
grep -q 'opponentName:root.boundedLabel(opponentName)' "$repo_dir/Panel.qml"
grep -q 'replace(/\[\\u0000-\\u001f\\u007f\]/g' "$repo_dir/Panel.qml"

echo "QML text-safety tests passed"
