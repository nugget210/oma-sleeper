#!/usr/bin/env bash
set -euo pipefail

# Sleeper keeps advancing its state week through the postseason, past the last
# week any fantasy league scores. The week was previously required to fall
# inside the fantasy season, so a postseason state failed validation, the
# refresh died, and the panel reported a connection problem in January. The
# week is clamped instead. A stub server is used because the live API only
# reports a postseason week in the postseason.
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/bin"

cat > "$test_root/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
output=""; url=""
while (( $# > 0 )); do
  case "$1" in
    --output|-o) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    --write-out|--max-filesize|--connect-timeout|--max-time|--proto|--retry|--retry-delay|--retry-max-time)
      shift 2 ;;
    *) shift ;;
  esac
done
case "$url" in
  */state/nfl)            printf '{"week":%s,"display_week":%s}' "${FAKE_WEEK:?}" "${FAKE_WEEK:?}" > "$output" ;;
  */league/*/users)       printf '[{"user_id":"u1","display_name":"Team","metadata":{}}]' > "$output" ;;
  */league/*/rosters)     printf '[{"roster_id":1,"owner_id":"u1","players":["p1"],"starters":["p1"]}]' > "$output" ;;
  */league/*/matchups/*)  printf '[{"roster_id":1,"matchup_id":1,"points":0,"players":["p1"],"starters":["p1"],"players_points":{"p1":0}}]' > "$output" ;;
  */league/*)             printf '{"league_id":"1234567890123456789","name":"League","season":"2026","roster_positions":["QB","BN"],"scoring_settings":{}}' > "$output" ;;
  */projections/*|*/stats/*) printf '{}' > "$output" ;;
  */scoreboard*)          printf '{"events":[]}' > "$output" ;;
  */players/nfl)          printf '{"p1":{"first_name":"A","last_name":"B","position":"QB","team":"CIN"}}' > "$output" ;;
  *)                      exit 1 ;;
esac
printf '200'
STUB
chmod +x "$test_root/bin/curl"

rendered_week() {
  local cache="$test_root/cache-$1"
  mkdir -p "$cache"
  FAKE_WEEK="$1" PATH="$test_root/bin:$PATH" XDG_CACHE_HOME="$cache" \
    "$repo_dir/bin/sleeper-matchup" 1234567890123456789 2>/dev/null | jq -r '.week' 2>/dev/null
}

check() {
  local label="$1" reported="$2" expected="$3" actual
  actual="$(rendered_week "$reported" || true)"
  [[ "$actual" == "$expected" ]] \
    || { echo "FAIL  $label (state week $reported rendered '$actual', expected $expected)" >&2; exit 1; }
  echo "PASS  $label"
}

check "a regular-season week is used as reported"       3  3
check "the final fantasy week is used as reported"      18 18
check "the first postseason week clamps into range"     19 18
check "a late postseason week clamps into range"        22 18
check "a week below the season clamps up"               0  1

echo "Postseason week tests passed"
