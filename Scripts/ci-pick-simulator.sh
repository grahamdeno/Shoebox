#!/bin/bash
# Prints the id of an iPhone simulator on an iOS 26 runtime (newest runtime, newest iPhone name sort). Fails if there is none.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
found = []
for runtime, devices in data.items():
    if "iOS-26" not in runtime:
        continue
    for d in devices:
        if d["name"].startswith("iPhone") and d.get("isAvailable", True):
            found.append((runtime, d["name"], d["udid"]))
if not found:
    sys.stderr.write("No iPhone simulator on an iOS 26 runtime is available.\n")
    sys.exit(1)
# Newest runtime first; among its iPhones prefer a plain numbered model over SE, Air or Pro names for a steady choice.
found.sort(key=lambda t: (t[0], t[1]), reverse=True)
runtime = found[0][0]
pool = [f for f in found if f[0] == runtime]
plain = [f for f in pool if f[1].replace("iPhone ", "").isdigit()] or pool
sys.stderr.write("Simulator: %s on %s\n" % (plain[0][1], runtime))
print(plain[0][2])
'
