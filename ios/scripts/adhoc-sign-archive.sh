#!/usr/bin/env bash
# Signs the archived app and its three extensions ad hoc ("-") with their entitlements,
# taken from the .entitlements files XcodeGen wrote into ios/Generated, with the App
# Group filled in from the built Info.plist. The export step then re-signs everything
# with the distribution certificate and keeps these entitlements, so the archive needs
# no development certificate, development profile or registered device.
#
# Usage: adhoc-sign-archive.sh <path to .xcarchive> [ios/Generated]
set -euo pipefail

archive="$1"
generated="${2:-ios/Generated}"
app="$archive/Products/Applications/ConcentrationMaxx.app"
work="${RUNNER_TEMP:-/tmp}/entitlements"

[ -d "$app" ] || { echo "::error::No app in $archive"; exit 1; }
group="$(/usr/libexec/PlistBuddy -c 'Print :CMXAppGroupID' "$app/Info.plist")"
mkdir -p "$work"

sign_bundle() {
  local bundle="$1"
  local source="$2"
  local expanded
  expanded="$work/$(basename "$source")"
  [ -f "$source" ] || { echo "::error::Missing $source (run xcodegen generate first)"; exit 1; }
  sed "s|\$(CMX_APP_GROUP)|$group|g" "$source" > "$expanded"
  if grep -q '\$(' "$expanded"; then
    echo "::error::$source still contains an unexpanded build setting"
    exit 1
  fi
  plutil -lint "$expanded" > /dev/null
  codesign --force --sign - --timestamp=none --entitlements "$expanded" "$bundle"
  echo "Signed $(basename "$bundle") ad hoc with $(basename "$source")"
}

# Inside out: anything nested first, then the extensions, then the app itself.
if [ -d "$app/Frameworks" ]; then
  find "$app/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 |
    while IFS= read -r -d '' item; do
      codesign --force --sign - --timestamp=none "$item"
      echo "Signed $(basename "$item") ad hoc"
    done
fi
for ext in CMXMonitor CMXShieldConfig CMXShieldAction; do
  sign_bundle "$app/PlugIns/$ext.appex" "$generated/$ext.entitlements"
done
sign_bundle "$app" "$generated/ConcentrationMaxx.entitlements"
