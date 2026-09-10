#!/usr/bin/env bash
set -euo pipefail

# The bar runs one panel per monitor, so several refreshes overlap and each one
# replaces cache files by rename while the others are linking them. That race
# was discarding whole refreshes. The shipped function is extracted here rather
# than reimplemented, so the test keeps exercising the real source.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
race_pid=""
cleanup() {
  local status=$?
  [[ -n "$race_pid" ]] && kill "$race_pid" 2>/dev/null
  wait 2>/dev/null || true
  rm -rf "$test_root"
  exit "$status"
}
trap cleanup EXIT

eval "$(awk '/^snapshot_cache_file\(\) \{$/,/^\}$/' "$repo_dir/bin/sleeper-matchup")"

die() { echo "sleeper-matchup: $*" >&2; exit 1; }
session_dir="$test_root/session"
mkdir -p "$session_dir"
temporary_files=()
snapshot_counter=0
target="$test_root/cache.json"

# An absent cache file is an ordinary state, not tampering: the caller downloads.
rm -f "$target"
snapshot_cache_file "$target" && { echo "FAIL  a missing cache target must report no snapshot" >&2; exit 1; }
echo "PASS  a missing cache target reports no snapshot"

printf '{"a":1}\n' > "$target"
snapshot_cache_file "$target" || { echo "FAIL  an existing cache target must be snapshotted" >&2; exit 1; }
[[ -f "$CACHE_FILE" && "$(cat "$CACHE_FILE")" == '{"a":1}' ]] \
  || { echo "FAIL  the snapshot must carry the cache contents" >&2; exit 1; }
echo "PASS  an existing cache target is snapshotted"

# Replace the target by rename continuously, the way a concurrent refresh does.
( while true; do
    printf '{"a":2}\n' > "$test_root/incoming.$$"
    mv -T -- "$test_root/incoming.$$" "$target" 2>/dev/null || true
  done ) &
race_pid=$!

failures=0
for _ in $(seq 1 400); do
  snapshot_cache_file "$target" || failures=$((failures + 1))
done
kill "$race_pid" 2>/dev/null
race_pid=""

(( failures == 0 )) || { echo "FAIL  $failures of 400 snapshots lost to a concurrent rename" >&2; exit 1; }
echo "PASS  a cache target being replaced by rename still snapshots"

# A target that is present but genuinely cannot be linked is still fatal. A
# session directory on another filesystem makes every link attempt fail with
# the target in place throughout.
if [[ -d /dev/shm && -w /dev/shm ]]; then
  foreign_dir="$(mktemp -d --tmpdir=/dev/shm oma-sleeper-test.XXXXXXXX)"
  if [[ "$(stat -c %d -- "$foreign_dir")" != "$(stat -c %d -- "$test_root")" ]]; then
    ( session_dir="$foreign_dir"
      snapshot_cache_file "$target" ) 2>/dev/null \
      && { rm -rf "$foreign_dir"; echo "FAIL  an unlinkable cache target must stay fatal" >&2; exit 1; }
    echo "PASS  an unlinkable cache target is still fatal"
  else
    echo "SKIP  an unlinkable cache target needs a second filesystem"
  fi
  rm -rf "$foreign_dir"
else
  echo "SKIP  an unlinkable cache target needs a second filesystem"
fi

echo "Cache snapshot race tests passed"
