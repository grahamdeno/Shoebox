#!/usr/bin/env python3
"""Prints Shoebox crash reports from the simulator as CI annotations, so a blank screenshot says why."""
import glob, json, os, sys
for path in sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/*.ips"))):
    if "shoebox" not in os.path.basename(path).lower():
        continue
    try:
        text = open(path).read()
        body = json.loads(text.split("\n", 1)[1])
    except Exception as e:
        print(f"::warning::{os.path.basename(path)}: unreadable ({e})")
        continue
    exc = body.get("exception", {})
    term = body.get("termination", {})
    print(f"::error::CRASH {os.path.basename(path)}: {exc.get('type')} {exc.get('signal')} {term.get('indicator', '')}")
    for t in body.get("threads", []):
        if t.get("triggered"):
            images = body.get("usedImages", [])
            for f in t.get("frames", [])[:14]:
                name = f.get("symbol") or (images[f["imageIndex"]].get("name") if "imageIndex" in f and f["imageIndex"] < len(images) else "?")
                print(f"::error::  {name} {f.get('sourceFile', '')}:{f.get('sourceLine', '')}")
    msg = body.get("asi") or {}
    for k, v in msg.items():
        print(f"::error::  {k}: {str(v)[:300]}")
