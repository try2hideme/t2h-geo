#!/usr/bin/env bash
# Build geosite.dat / geoip.dat / sing-box .srs into $OUT (default ./out).
# Needs: go, git, curl, jq, python3, sing-box (for .srs compile).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/versions.env"
WORK=${WORK:-$ROOT/.work}
OUT=${OUT:-$ROOT/out}
SINGBOX=${SINGBOX:-sing-box}
export GOTOOLCHAIN=${GOTOOLCHAIN:-auto}
rm -rf "$WORK" "$OUT"; mkdir -p "$WORK/bin" "$OUT/sing-box"

latest_tag() { git ls-remote --tags "https://github.com/$1.git" | awk '{print $2}' |
  sed -E 's@refs/tags/@@; s@\^\{\}@@' | grep -E '^[0-9]{12}$' | sort | tail -n1; }
ROSCOM_GEOSITE_TAG=${ROSCOM_GEOSITE_TAG:-$(latest_tag hydraponique/roscomvpn-geosite)}
ROSCOM_GEOIP_TAG=${ROSCOM_GEOIP_TAG:-$(latest_tag hydraponique/roscomvpn-geoip)}
[ -n "$ROSCOM_GEOSITE_TAG" ] && [ -n "$ROSCOM_GEOIP_TAG" ]
echo "upstream: geosite=$ROSCOM_GEOSITE_TAG geoip=$ROSCOM_GEOIP_TAG"

CLONE="git -c advice.detachedHead=false clone -q --depth 1 --branch"
$CLONE "$DLC_TAG" https://github.com/v2fly/domain-list-community "$WORK/dlc"
$CLONE "$GEOIP_TAG" https://github.com/v2fly/geoip "$WORK/geoip"
$CLONE "$ROSCOM_GEOSITE_TAG" https://github.com/hydraponique/roscomvpn-geosite "$WORK/up-geosite"
(cd "$WORK/dlc" && go build -o "$WORK/bin/dlc" ./)
(cd "$WORK/geoip" && go build -o "$WORK/bin/geoip" ./)

### geosite ###
rm -rf "$WORK/dlc/data"; mkdir -p "$WORK/dlc/data"
cp -a "$WORK/up-geosite/data/." "$WORK/dlc/data/"
cp -a "$ROOT/data/geosite/." "$WORK/dlc/data/"   # ours override same-named upstream files
EXPORT=$(cd "$WORK/dlc/data" && ls | paste -sd,)
(cd "$WORK/dlc" && "$WORK/bin/dlc" -datapath=./data -outputdir="$OUT" -outputname=geosite.dat -exportlists="$EXPORT")
mkdir -p "$WORK/lists"; mv "$OUT"/*.txt "$WORK/lists/"
test -s "$OUT/geosite.dat"

### geoip ###
GI="$WORK/gi"; mkdir -p "$GI"
curl -fsSL --retry 3 -o "$GI/upstream-geoip.dat" \
  "https://github.com/hydraponique/roscomvpn-geoip/releases/download/$ROSCOM_GEOIP_TAG/geoip.dat"
curl -fsSL --retry 3 -o "$GI/upstream-geoip.dat.sha256" \
  "https://github.com/hydraponique/roscomvpn-geoip/releases/download/$ROSCOM_GEOIP_TAG/geoip.dat.sha256"
(cd "$GI" && awk '{print $1"  upstream-geoip.dat"}' upstream-geoip.dat.sha256 | sha256sum -c -)
curl -fsSL --retry 3 -o "$GI/telegram-cidr.txt" https://core.telegram.org/resources/cidr.txt
test "$(grep -c / "$GI/telegram-cidr.txt")" -ge 5
cp "$ROOT/data/geoip/t2h-direct-extra.txt" "$GI/"
cat > "$GI/config.json" <<JSON
{
  "input": [
    { "type": "v2rayGeoIPDat", "action": "add", "args": { "uri": "./upstream-geoip.dat" } },
    { "type": "text", "action": "add", "args": { "name": "t2h-direct-extra", "uri": "./t2h-direct-extra.txt" } },
    { "type": "text", "action": "add", "args": { "name": "t2h-proxy-ip", "uri": "./telegram-cidr.txt" } }
  ],
  "output": [
    { "type": "v2rayGeoIPDat", "action": "output", "args": { "outputDir": "$OUT", "outputName": "geoip.dat" } },
    { "type": "text", "action": "output", "args": { "outputDir": "$WORK/iptext" } }
  ]
}
JSON
(cd "$GI" && "$WORK/bin/geoip" -c config.json)
test -s "$OUT/geoip.dat"

### sing-box .srs ###
for name in t2h-direct t2h-proxy t2h-block t2h-lte-whitelist category-ru; do
  # lists: "domain:x", "full:x", "regexp:x", "keyword:x" with optional " @attr"
  sed -E 's/[[:space:]]+@.*$//' "$WORK/lists/$name.txt" | grep -v '^$' | jq -Rn '
    [inputs | capture("^(?<t>[a-z]+):(?<v>.+)$")] as $r
    | def pick($t): [$r[] | select(.t==$t) | .v];
      {version:3, rules:[ {domain: pick("full"), domain_suffix: pick("domain"),
        domain_keyword: pick("keyword"), domain_regex: pick("regexp")}
        | with_entries(select(.value|length>0)) ]}
    | if (.rules[0]|length)==0 then .rules=[] else . end' > "$WORK/$name.json"
  "$SINGBOX" rule-set compile --output "$OUT/sing-box/geosite-$name.srs" "$WORK/$name.json"
done
for name in direct private t2h-direct-extra t2h-proxy-ip; do
  jq -Rn '{version:3, rules:[{ip_cidr:[inputs|select(length>0)]}]}' "$WORK/iptext/$name.txt" > "$WORK/ip-$name.json"
  "$SINGBOX" rule-set compile --output "$OUT/sing-box/geoip-$name.srs" "$WORK/ip-$name.json"
done

### stats / checksums ###
python3 "$ROOT/scripts/datstat.py" geosite "$OUT/geosite.dat" > "$WORK/gs.json"
python3 "$ROOT/scripts/datstat.py" geoip "$OUT/geoip.dat" > "$WORK/gi.json"
jq -n --slurpfile s "$WORK/gs.json" --slurpfile i "$WORK/gi.json" \
  --arg gst "$ROSCOM_GEOSITE_TAG" --arg git "$ROSCOM_GEOIP_TAG" \
  '{upstream:{geosite:$gst,geoip:$git},geosite:$s[0],geoip:$i[0]}' > "$OUT/stats.json"
(cd "$OUT" && sha256sum geosite.dat > geosite.dat.sha256 && sha256sum geoip.dat > geoip.dat.sha256)
tar -czf "$OUT/sing-box.tar.gz" -C "$OUT" sing-box
echo "built into $OUT"
