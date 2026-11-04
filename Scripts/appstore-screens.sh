#!/bin/sh
# The App Store set: six screens on the 6.9-inch simulator, with real photos for the sample posts.
# Usage: Scripts/appstore-screens.sh <simulator id> <folder of demo photos>
set -e
SIM="$1"
PHOTOS="$2"
APP=$(find build/Build/Products -name "Shoebox.app" -maxdepth 3 | head -1)
xcrun simctl boot "$SIM" || true
xcrun simctl bootstatus "$SIM" -b
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl spawn "$SIM" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
DATA=$(xcrun simctl get_app_container "$SIM" com.grahamdeno.shoebox data)
mkdir -p "$DATA/Documents/demo-photos"
cp "$PHOTOS"/*.jpg "$DATA/Documents/demo-photos/" 2>/dev/null || echo "::warning::No demo photos; the drawn stand-ins are used."
mkdir -p screens
shot() { # look screen colors file
  xcrun simctl ui "$SIM" appearance "$1"
  xcrun simctl terminate "$SIM" com.grahamdeno.shoebox 2>/dev/null || true
  xcrun simctl launch "$SIM" com.grahamdeno.shoebox -demo YES -screen "$2" -colors "$3" >/dev/null
  sleep 10
  xcrun simctl spawn "$SIM" launchctl list 2>/dev/null | grep -q com.grahamdeno.shoebox || echo "::error::$4: the app is not running (crashed?)"
  xcrun simctl io "$SIM" screenshot "screens/$4.png" >/dev/null 2>&1
}
shot light today pistachio 1-today
shot light away pistachio 2-put-away
shot light box pistachio 3-shoebox
shot light opened pistachio 4-opened
shot light add pistachio 5-keep
shot dark settings stone 6-stone-settings
ls -l screens
