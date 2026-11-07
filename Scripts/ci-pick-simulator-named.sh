#!/bin/bash
# Prints the id of the first available iPhone simulator on the newest iOS 26 runtime whose name starts with one of the
# given names, tried in order ("iPhone SE" "iPhone 16e"). Falls back to the smallest-named iPhone there. For ux-audit.yml.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1:]
data = json.load(sys.stdin)["devices"]
runtimes = sorted([r for r in data if "iOS-26" in r], reverse=True)
if not runtimes:
    sys.stderr.write("No iOS 26 runtime.\n"); sys.exit(1)
pool = [d for d in data[runtimes[0]] if d["name"].startswith("iPhone")]
sys.stderr.write("Available: %s\n" % ", ".join(d["name"] for d in pool))
for w in want:
    for d in pool:
        if d["name"].startswith(w):
            sys.stderr.write("Simulator: %s\n" % d["name"]); print(d["udid"]); sys.exit(0)
pool.sort(key=lambda d: d["name"])
sys.stderr.write("Simulator (fallback): %s\n" % pool[0]["name"]); print(pool[0]["udid"])
' "$@"
