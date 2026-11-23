#!/usr/bin/env bash
# Selects /Applications/Xcode_<version>.app when the runner has it, otherwise keeps the
# runner's default Xcode (with a warning). Then checks that the iOS SDK is 26 or newer,
# which App Store Connect requires for uploads.
#
# Usage: ios/scripts/select-xcode.sh 26.6
set -euo pipefail

wanted="${1:-}"
if [ -n "$wanted" ] && [ -d "/Applications/Xcode_${wanted}.app" ]; then
  sudo xcode-select --switch "/Applications/Xcode_${wanted}.app/Contents/Developer"
else
  echo "::warning::Xcode ${wanted:-<none>} is not installed on this runner; using $(xcode-select --print-path)"
fi

xcodebuild -version
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "iOS SDK ${sdk_version}"
if [ "${sdk_version%%.*}" -lt 26 ]; then
  echo "::error::The selected Xcode has iOS SDK ${sdk_version}; App Store Connect requires the iOS 26 SDK or later."
  exit 1
fi
