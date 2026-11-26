#!/usr/bin/env bash
# Generate happ/t2h.json and happ/t2h.deeplink for a release tag.
# Usage: happ.sh <owner/repo> <tag>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=$1; TAG=$2
BASE="https://cdn.jsdelivr.net/gh/$REPO@$TAG/release"
jq -n --arg ip "$BASE/geoip.dat" --arg site "$BASE/geosite.dat" --arg ts "$(date -u +%s)" '{
  Name: "t2h",
  GlobalProxy: "true",
  UseChunkFiles: "false",
  RemoteDns: "8.8.8.8",
  DomesticDns: "77.88.8.8",
  RemoteDNSType: "DoH",
  RemoteDNSDomain: "https://8.8.8.8/dns-query",
  RemoteDNSIP: "8.8.8.8",
  DomesticDNSType: "DoH",
  DomesticDNSDomain: "https://77.88.8.8/dns-query",
  DomesticDNSIP: "77.88.8.8",
  Geoipurl: $ip,
  Geositeurl: $site,
  LastUpdated: $ts,
  DnsHosts: { "lkfl2.nalog.ru": "213.24.64.175", "lknpd.nalog.ru": "213.24.64.181" },
  RouteOrder: "block-proxy-direct",
  DirectSites: [], DirectIp: [], ProxySites: [], ProxyIp: [], BlockSites: [], BlockIp: [],
  DomainStrategy: "IPIfNonMatch",
  FakeDNS: "true"
}' > "$ROOT/happ/t2h.json"
printf 'happ://routing/add/%s' "$(jq -c . "$ROOT/happ/t2h.json" | base64 -w0)" > "$ROOT/happ/t2h.deeplink"
echo "happ profile -> tag $TAG"
