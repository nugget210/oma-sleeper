#!/usr/bin/env bash
set -euo pipefail

# Structural safety checks on the QML. These assert properties that must hold
# for the panel to be safe with remote and user-supplied text, and are matched
# loosely enough that reformatting or renaming does not fail them. Behavioural
# coverage of the validators themselves lives in tests/test-alert-logic.sh.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
qml_files=(Panel.qml TeamColumn.qml PlayerRow.qml)
qml_paths=("${qml_files[@]/#/$repo_dir/}")

failures=0
check() {
  local label="$1"
  shift
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    failures=$((failures + 1))
  fi
}

# Every Text item must render as plain text. Rich text would let a player or
# team name from the Sleeper API inject markup into the panel.
same_count() {
  local pattern_a="$1" pattern_b="$2" a b
  a="$(rg -o "$pattern_a" "${qml_paths[@]}" | wc -l)"
  b="$(rg -o "$pattern_b" "${qml_paths[@]}" | wc -l)"
  [[ "$a" -eq "$b" && "$a" -gt 0 ]]
}
check "every Text item is Text.PlainText" \
  same_count '\bText\s*\{' 'textFormat:\s*Text\.PlainText'

# Every text input must be length-bounded, so a pasted value cannot grow the
# stored settings entry without limit.
text_fields="$(rg -o '\bTextField\s*\{' "$repo_dir/Panel.qml" | wc -l)"
bounded_fields="$(rg -o 'maximumLength:' "$repo_dir/Panel.qml" | wc -l)"
check "every TextField bounds its length ($text_fields fields, $bounded_fields bounded)" \
  test "$text_fields" -eq "$bounded_fields"

check "a label length bound is defined" \
  grep -Eq 'readonly property int maxLabelLength: [0-9]+' "$repo_dir/Panel.qml"

# The persisted settings entry carries user input and remote-derived text, so
# saveEntry must run it back through the validators before publishing it.
save_entry="$(awk '/^  function saveEntry/,/^  }$/' "$repo_dir/Panel.qml")"
check "saveEntry bounds the team label" \
  grep -Eq 'shortName *= *root\.boundedLabel' <<<"$save_entry"
check "saveEntry bounds the opponent label" \
  grep -Eq 'opponentName *= *root\.boundedLabel' <<<"$save_entry"
check "saveEntry validates the alert sound" \
  grep -Eq 'scoreSound *= *root\.soundChoice' <<<"$save_entry"

# Alert playback and notification must go through the bundled helper scripts
# with argument vectors, never a shell string that could be interpolated.
check "alert playback uses the bundled helper" \
  grep -q 'root.pluginFile("bin/play-alert")' "$repo_dir/Panel.qml"
check "notifications use the bundled helper" \
  grep -q 'root.pluginFile("bin/notify-alert")' "$repo_dir/Panel.qml"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures QML safety check(s) failed"
  exit 1
fi
echo "QML text-safety tests passed"
