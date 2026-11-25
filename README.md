# t2h-geo

Custom `geosite.dat` / `geoip.dat` (v2ray/xray format) and sing-box rule-sets (`.srs`) for routing
RU traffic. Built daily by GitHub Actions on top of the public roscomvpn lists, plus our own `t2h-*` categories.

## Categories

geosite.dat
- every roscomvpn-geosite category as is (`category-ru`, `private`, `whitelist`, `youtube`, `telegram`, ...)
- `t2h-direct` - Russian services and things that must go direct (everything roscomvpn DEFAULT sends direct by geosite + initial seed)
- `t2h-proxy` - forced through the proxy (YouTube/googlevideo, Google Play/GMS, Telegram, GitHub, novayagazeta.ru, ...)
- `t2h-block` - Microsoft telemetry, torrent trackers, ads. Russian ad networks used by apps (adfox, adriver, mail.ru ads) are intentionally not blocked
- `t2h-lte-whitelist` - domains of mobile operator whitelists (currently = upstream `whitelist`)

geoip.dat
- every roscomvpn-geoip category (`direct`, `private`, `whitelist`)
- `t2h-direct-extra` - extra direct networks, `t2h-proxy-ip` - Telegram networks (official `cidr.txt`, refreshed at every build)

sing-box rule-sets (`release/sing-box/`): `geosite-{t2h-direct,t2h-proxy,t2h-block,t2h-lte-whitelist,category-ru}.srs`,
`geoip-{direct,private,t2h-direct-extra,t2h-proxy-ip}.srs`. Same files as `sing-box.tar.gz` in the release.

## Download

- Release assets: `https://github.com/try2hideme/t2h-geo/releases/latest/download/geosite.dat` (and `geoip.dat`, `*.sha256`)
- jsDelivr (pin a release tag): `https://cdn.jsdelivr.net/gh/try2hideme/t2h-geo@<TAG>/release/geosite.dat`
  and `.../release/geoip.dat`

## Happ routing profile

`happ/t2h.json` is a profile without rules: it only substitutes `Geoipurl` / `Geositeurl` (our files, pinned to the
latest release tag) and sets DNS. The rules themselves live in the xray JSON template. CI regenerates the profile
and `happ/t2h.deeplink` (`happ://routing/add/<base64>`) on every release. Replace `add` with `onadd` to also activate
the profile right after adding. The current deeplink is the content of `happ/t2h.deeplink`.

`tests/xray-template.json` is the reference xray template (rule order: block, direct, proxy, geoip direct, proxy-ip,
bittorrent, final proxy). Note: because `regexp:.*\.ru$` sits in the direct rule that precedes `geosite:t2h-proxy`,
`.ru` domains listed in `t2h-proxy` (e.g. novayagazeta.ru) still go direct in this order. Put the `t2h-proxy` rule
before the direct rule if they must be proxied.

## How the build works

`scripts/build.sh`: clones pinned [domain-list-community](https://github.com/v2fly/domain-list-community) and
[v2fly/geoip](https://github.com/v2fly/geoip) (tags in `versions.env`), takes the latest roscomvpn-geosite tag data,
overlays `data/geosite/*`, builds `geosite.dat`; takes the latest roscomvpn-geoip release `geoip.dat`, adds
`data/geoip/*` and Telegram CIDRs, builds `geoip.dat`; compiles `.srs` with sing-box.
`scripts/check.sh` (failure = no release): required categories non-empty, no category shrinks by more than 30 %
vs the previous release, `xray run -test` on `tests/xray-template.json` with the built dat, `sing-box check` with the built `.srs`.
A release (tag `YYYYMMDDHHMM`, commit to `release/`) is made only if `geosite.dat` or `geoip.dat` changed.
Triggers: daily cron, manual run, push to `main` (data/scripts).

## Adding a domain

Edit `data/geosite/t2h-direct`, `t2h-proxy`, `t2h-block` (or `t2h-lte-whitelist`) and push to `main`.
Syntax is domain-list-community: `domain:example.com` (with subdomains), `full:host.example.com`, `keyword:foo`,
`regexp:^x$`, `include:other-category`. A same-named file in `data/geosite/` overrides the upstream one.
IP networks: `data/geoip/t2h-direct-extra.txt` (one CIDR per line). No secrets, no node addresses here: the repo is public.

## Sources and licenses

- [hydraponique/roscomvpn-geosite](https://github.com/hydraponique/roscomvpn-geosite) - domain lists (MIT, derived from v2fly)
- [hydraponique/roscomvpn-geoip](https://github.com/hydraponique/roscomvpn-geoip) - `geoip.dat` used as input (no license file;
  its README lists GeoLite2, IPinfo, DB-IP and other sources, see their terms)
- [hydraponique/roscomvpn-routing](https://github.com/hydraponique/roscomvpn-routing) - profile format reference only
- [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) - builder (MIT)
- [v2fly/geoip](https://github.com/v2fly/geoip) - builder (CC-BY-SA-4.0)
- Telegram `https://core.telegram.org/resources/cidr.txt` - public list of Telegram networks
- Our scripts and `data/` seed: MIT (see `LICENSE`). Generated dat/srs files contain third-party data under the terms above.
