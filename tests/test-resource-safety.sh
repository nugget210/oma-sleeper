#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
cleanup() {
  local status=$?
  rm -rf "$test_root"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$test_root/bin"
cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=""
max_bytes=""
url=""
while (( $# > 0 )); do
  case "$1" in
    --output|-o)
      output="$2"
      shift 2
      ;;
    --write-out|--max-filesize|--connect-timeout|--max-time|--proto)
      [[ "$1" == --max-filesize ]] && max_bytes="$2"
      shift 2
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s\t%s\t%s\n' "$url" "$output" "$max_bytes" >> "${CURL_LOG:?}"

case "$url" in
  */state/nfl)
    if [[ "${FAKE_MODE:-normal}" == malicious_week ]]; then
      printf '{"week":"1+a[$(touch /tmp/oma-sleeper-arithmetic-injection)]"}' > "$output"
    elif [[ "${FAKE_MODE:-normal}" == oversized_state ]]; then
      {
        printf '{"week":"'
        printf '%070000d' 0
        printf '"}'
      } > "$output"
    else
      printf '{"week":18}' > "$output"
    fi
    ;;
  */league/*/users)
    if [[ "${FAKE_MODE:-normal}" == too_many_users ]]; then
      jq -nc '[range(0;65) | {user_id:("u" + tostring), display_name:"Team", metadata:{}}]' > "$output"
    else
      printf '[{"user_id":"u1","display_name":"Team","metadata":{}}]' > "$output"
    fi
    ;;
  */league/*/rosters)
    printf '[{"roster_id":1,"owner_id":"u1","players":["p1"],"starters":["p1"]}]' > "$output"
    ;;
  */league/*/matchups/*)
    printf '[{"roster_id":1,"matchup_id":1,"points":0,"players":["p1"],"starters":["p1"],"players_points":{"p1":0}}]' > "$output"
    ;;
  */league/*)
    if [[ "${FAKE_MODE:-normal}" == malicious_season ]]; then season='../../escaped'; else season='2026'; fi
    printf '{"league_id":"1234567890123456789","name":"League","season":"%s","roster_positions":["QB","BN"],"scoring_settings":{}}' "$season" > "$output"
    ;;
  */projections/*)
    printf '{}' > "$output"
    ;;
  */scoreboard*)
    printf '{"events":[]}' > "$output"
    ;;
  */players/nfl)
    printf '{"p1":{"first_name":"A","last_name":"B","position":"QB","team":"CIN"}}' > "$output"
    ;;
  *)
    exit 1
    ;;
esac

printf '200'
EOF
chmod +x "$test_root/bin/curl"

run_failing_case() {
  local mode="$1" cache="$2"
  shift 2
  mkdir -p "$cache"
  : > "$test_root/curl.log"
  set +e
  FAKE_MODE="$mode" CURL_LOG="$test_root/curl.log" PATH="$test_root/bin:$PATH" XDG_CACHE_HOME="$cache" \
    "$repo_dir/bin/sleeper-matchup" "$@" >"$test_root/output" 2>"$test_root/error"
  status=$?
  set -e
  [[ $status -ne 0 ]]
}

rm -f /tmp/oma-sleeper-arithmetic-injection
run_failing_case malicious_week "$test_root/week-cache" 1234567890123456789 auto force
[[ ! -e /tmp/oma-sleeper-arithmetic-injection ]]
grep -q 'invalid week' "$test_root/error"

run_failing_case normal "$test_root/explicit-week-cache" 1234567890123456789 '1+a[0]' force
[[ ! -s "$test_root/curl.log" ]]
grep -q 'invalid week' "$test_root/error"

run_failing_case malicious_season "$test_root/season-cache" 1234567890123456789 1 force
[[ ! -e "$test_root/escaped.json" && ! -e "$test_root/season-cache/escaped.json" ]]
grep -q 'invalid season' "$test_root/error"

run_failing_case oversized_state "$test_root/size-cache" 1234567890123456789 auto force
[[ ! -e "$test_root/size-cache/oma-sleeper/nfl-state.json" ]]

run_failing_case too_many_users "$test_root/collection-cache" 1234567890123456789 1 force

symlink_cache="$test_root/symlink-cache"
mkdir -p "$symlink_cache/oma-sleeper"
printf 'unchanged' > "$test_root/outside"
ln -s "$test_root/outside" "$symlink_cache/oma-sleeper/league-1234567890123456789.json"
run_failing_case normal "$symlink_cache" 1234567890123456789 1 normal
[[ "$(cat "$test_root/outside")" == unchanged ]]
grep -q 'must not be a symlink' "$test_root/error"

directory_link_cache="$test_root/directory-link-cache"
mkdir -p "$directory_link_cache" "$test_root/linked-cache-target"
ln -s "$test_root/linked-cache-target" "$directory_link_cache/oma-sleeper"
run_failing_case normal "$directory_link_cache" 1234567890123456789 1 normal
grep -q 'cache directory must not be a symlink' "$test_root/error"

normal_cache="$test_root/normal-cache"
mkdir -p "$normal_cache"
: > "$test_root/curl.log"
FAKE_MODE=normal CURL_LOG="$test_root/curl.log" PATH="$test_root/bin:$PATH" XDG_CACHE_HOME="$normal_cache" \
  "$repo_dir/bin/sleeper-matchup" 1234567890123456789 18 force > "$test_root/output"
jq -e '.week == 18 and (.teams | length) == 1 and (.games | length) == 1' "$test_root/output" >/dev/null

matchup_requests="$(awk -F '\t' '$1 ~ /\/matchups\/[0-9]+$/ {count++} END {print count+0}' "$test_root/curl.log")"
[[ "$matchup_requests" -eq 5 ]]
mapfile -t download_paths < <(awk -F '\t' '$2 != "" {print $2}' "$test_root/curl.log")
(( ${#download_paths[@]} >= 10 ))
for path in "${download_paths[@]}"; do
  [[ "$path" == "$normal_cache/oma-sleeper/".oma-sleeper.* ]]
done
[[ -z "$(printf '%s\n' "${download_paths[@]}" | sort | uniq -d)" ]]
awk -F '\t' '$3 !~ /^[0-9]+$/ || $3 <= 0 {exit 1}' "$test_root/curl.log"
[[ "$(stat -c %a "$normal_cache/oma-sleeper")" == 700 ]]
[[ -z "$(find "$normal_cache/oma-sleeper" -maxdepth 1 -type l -print -quit)" ]]
[[ -z "$(find "$normal_cache/oma-sleeper" -maxdepth 1 -name '*.tmp' -print -quit)" ]]
while IFS= read -r file; do [[ "$(stat -c %a "$file")" == 600 ]]; done \
  < <(find "$normal_cache/oma-sleeper" -maxdepth 1 -type f -name '*.json')

echo "Resource-safety tests passed"
