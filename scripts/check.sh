#!/usr/bin/env bash
# Validate a build in $OUT. Any failure = no release.
# Optional: PREV_STATS=path/to/previous/stats.json for the size-drop check.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/out}
XRAY=${XRAY:-xray}
SINGBOX=${SINGBOX:-sing-box}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
S="$OUT/stats.json"
fail() { echo "CHECK FAILED: $*" >&2; exit 1; }

# 1. required categories present and non-empty (t2h-lte-whitelist may be empty)
for c in t2h-direct t2h-proxy t2h-block category-ru private; do
  n=$(jq -r --arg c "$c" '.geosite[$c] // 0' "$S"); [ "$n" -gt 0 ] || fail "geosite:$c empty/missing"
done
jq -e '.geosite["t2h-lte-whitelist"] != null' "$S" >/dev/null || fail "geosite:t2h-lte-whitelist missing"
for c in direct private t2h-direct-extra t2h-proxy-ip; do
  n=$(jq -r --arg c "$c" '.geoip[$c] // 0' "$S"); [ "$n" -gt 0 ] || fail "geoip:$c empty/missing"
done

# 2. no category may shrink by more than 30% vs previous release
if [ -n "${PREV_STATS:-}" ] && [ -s "$PREV_STATS" ]; then
  for kind in geosite geoip; do
    jq -r --arg k "$kind" --slurpfile p "$PREV_STATS" \
      '.[$k] | to_entries[] | select(($p[0][$k][.key] // 0) > 10 and .value < ($p[0][$k][.key] * 0.7))
       | "\($k):\(.key) \($p[0][$k][.key]) -> \(.value)"' "$S" | tee "$TMP/drop"
    [ ! -s "$TMP/drop" ] || fail "category shrank by more than 30%"
    # categories that disappeared entirely
    jq -r --arg k "$kind" --slurpfile p "$PREV_STATS" \
      '. as $n | $p[0][$k] | to_entries[] | select(.value > 10 and ($n[$k][.key] // 0) == 0) | "\($k):\(.key) disappeared"' "$S" | tee "$TMP/gone"
    [ ! -s "$TMP/gone" ] || fail "category disappeared"
  done
fi

# 3. xray config test with the built dat files (every rule referencing our categories)
export XRAY_LOCATION_ASSET="$OUT"
"$XRAY" run -test -c "$ROOT/tests/xray-template.json" | tail -n1 | grep -q 'Configuration OK' || fail "xray -test"
echo "xray -test OK"

# 4. sing-box check with local .srs
sed "s#RULESETS#$OUT/sing-box#" "$ROOT/tests/singbox-test.json" > "$TMP/sb.json"
"$SINGBOX" check -c "$TMP/sb.json" || fail "sing-box check"
echo "sing-box check OK"

echo "ALL CHECKS PASSED"
