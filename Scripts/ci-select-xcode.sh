#!/bin/bash
# Selects the pinned, released Xcode. Change XCODE_APP in one place (the workflows' env) when moving to a newer one.
# Fails loudly, listing what is installed, instead of quietly using a different version.
set -euo pipefail
APP="${XCODE_APP:?XCODE_APP is not set}"
if [ ! -d "$APP" ]; then
  echo "::error::$APP is not installed on this runner. Installed:"
  ls -d /Applications/Xcode*.app || true
  exit 1
fi
sudo xcode-select -s "$APP"
xcodebuild -version
