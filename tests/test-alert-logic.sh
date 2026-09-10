#!/usr/bin/env bash
set -euo pipefail

# Runs tests/alert-logic.js against the functions in Panel.qml and PlayerRow.qml.
#
# Panel.qml is injected as a JSON string literal rather than read by the test
# itself, so the harness needs no file API and runs on whichever JavaScript
# engine happens to be present. No engine is a required dependency of this
# plugin, so the test reports a skip instead of failing when none is installed.

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

engine=""
engine_args=()
for candidate in node bun qjs deno; do
  if command -v "$candidate" >/dev/null 2>&1; then
    engine="$candidate"
    [[ "$candidate" == deno ]] && engine_args=(run --quiet)
    break
  fi
done

if [[ -z "$engine" ]]; then
  echo "Alert logic tests skipped (no JavaScript engine: node, bun, qjs, or deno)"
  exit 0
fi

work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

{
  printf 'const QML_SOURCE = '
  jq -Rs . <"$repo_dir/Panel.qml"
  printf ';\n'
  printf 'const PLAYER_ROW_SOURCE = '
  jq -Rs . <"$repo_dir/PlayerRow.qml"
  printf ';\n'
  cat "$repo_dir/tests/alert-logic.js"
} >"$work_dir/run.js"

"$engine" "${engine_args[@]}" "$work_dir/run.js"
