#!/bin/bash
# Checks the exported IPA still carries the entitlements Shoebox needs: the App Group in the app and the share
# extension, and the iCloud container in the app. The archive is built unsigned and stamped, so this proves the
# export kept them. Usage: Scripts/check_entitlements.sh path/to/Shoebox.ipa
set -euo pipefail
IPA="${1:?path to the ipa}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"
APP="$(ls -d "$WORK"/Payload/*.app | head -1)"
APPEX="$(ls -d "$APP"/PlugIns/*.appex | head -1)"
fail=0
need() { # file, text, label
  if codesign -d --entitlements :- "$1" 2>/dev/null | grep -q "$2"; then
    echo "ok: $3"
  else
    echo "::error::Missing in the exported build: $3"; fail=1
  fi
}
need "$APP"   "group.com.grahamdeno.shoebox"        "App Group in the app"
need "$APPEX" "group.com.grahamdeno.shoebox"        "App Group in the share extension"
need "$APP"   "iCloud.com.grahamdeno.shoebox"       "iCloud container in the app"
need "$APP"   "com.apple.developer.icloud-services" "iCloud services in the app"
exit $fail
