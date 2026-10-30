#!/bin/sh
# Screenshots of each screen, day and night, both palettes, in the simulator. Sample data only (-demo).
set -e
SIM="$1"
APP=$(find build/Build/Products -name "Shoebox.app" -maxdepth 3 | head -1)
xcrun simctl boot "$SIM" || true
xcrun simctl bootstatus "$SIM" -b
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$SIM" "$APP"
mkdir -p screens
for look in light dark; do
  xcrun simctl ui "$SIM" appearance $look
  for palette in plum gold; do
    for screen in coming detail capture everything onboarding post; do
      [ "$palette" = gold ] && [ "$screen" != coming ] && [ "$screen" != detail ] && continue
      extra=""; [ "$palette" = gold ] && extra="-gold"
      xcrun simctl terminate "$SIM" com.grahamdeno.shoebox 2>/dev/null || true
      xcrun simctl launch "$SIM" com.grahamdeno.shoebox -demo -screen $screen $extra >/dev/null
      sleep 7
      xcrun simctl io "$SIM" screenshot "screens/$palette-$look-$screen.png" >/dev/null 2>&1
    done
  done
done
ls -l screens
