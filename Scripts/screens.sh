#!/bin/sh
# Screenshots of each screen, light and dark, in the simulator, with sample data (-demo).
set -e
SIM="$1"
APP=$(find build/Build/Products -name "Shoebox.app" -maxdepth 3 | head -1)
xcrun simctl boot "$SIM" || true
xcrun simctl bootstatus "$SIM" -b
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl spawn "$SIM" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
mkdir -p screens
SCREENS="${SCREENS:-today lid opened box add clear welcome share time learn settings}"
for look in light dark; do
  xcrun simctl ui "$SIM" appearance $look
  for screen in $SCREENS; do
    xcrun simctl terminate "$SIM" com.grahamdeno.shoebox 2>/dev/null || true
    xcrun simctl launch "$SIM" com.grahamdeno.shoebox -demo YES -screen $screen >/dev/null
    sleep 9
    xcrun simctl spawn "$SIM" launchctl list 2>/dev/null | grep -q com.grahamdeno.shoebox || echo "::error::$look-$screen: the app is not running (crashed?)"
    xcrun simctl io "$SIM" screenshot "screens/$look-$screen.png" >/dev/null 2>&1
  done
done
ls -l screens
python3 Scripts/crash_report.py || true
