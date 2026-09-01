#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/cache"
cat > "$test_root/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=""
while (( $# > 0 )); do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    --write-out)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -z "$output" ]] || printf '{"message":"Not Found"}' > "$output"
printf '404'
exit 22
EOF
chmod +x "$test_root/bin/curl"

set +e
PATH="$test_root/bin:$PATH" XDG_CACHE_HOME="$test_root/cache" \
  "$repo_dir/bin/sleeper-matchup" 1234567890123456789 1 force \
  >"$test_root/output" 2>"$test_root/error"
status=$?
set -e

[[ $status -eq 44 ]]
grep -q '^League not found$' "$test_root/error"

echo "Invalid-league test passed"
