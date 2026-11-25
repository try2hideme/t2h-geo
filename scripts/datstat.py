#!/usr/bin/env python3
"""Count entries per category in a v2ray geosite.dat / geoip.dat (stdlib protobuf walker).
Usage: datstat.py geosite|geoip FILE  -> JSON {category: count}"""
import json, sys

def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1
        r |= (c & 0x7F) << s; s += 7
        if not c & 0x80:
            return r, i

def fields(b):
    i = 0
    while i < len(b):
        k, i = varint(b, i)
        f, w = k >> 3, k & 7
        if w == 0:
            v, i = varint(b, i)
        elif w == 2:
            n, i = varint(b, i); v = b[i:i + n]; i += n
        elif w == 1:
            v = b[i:i + 8]; i += 8
        elif w == 5:
            v = b[i:i + 4]; i += 4
        else:
            raise ValueError("bad wire type")
        yield f, v

def main():
    path = sys.argv[2]  # argv[1] (geosite|geoip) kept for readability: both use field 2
    out = {}
    for f, ent in fields(open(path, "rb").read()):
        if f != 1:
            continue
        code, n = None, 0
        for g, v in fields(ent):
            if g == 1:
                code = v.decode()
            elif g == 2:
                n += 1
        out[code.lower()] = n
    json.dump(out, sys.stdout, sort_keys=True, indent=0)

main()
