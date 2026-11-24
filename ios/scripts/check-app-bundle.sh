#!/usr/bin/env bash
# Checks a built ConcentrationMaxx.app before it goes anywhere: the three extensions are
# embedded, every bundle has the same version and build number, and every binary is
# signed with the Family Controls entitlement and the App Group. Prints no certificate
# or account details, so it is safe in public logs.
#
# Usage: check-app-bundle.sh <path to ConcentrationMaxx.app> <expected build number> [distribution]
#   With "distribution", also checks what App Store signing adds (beta-reports-active,
#   no get-task-allow).
set -euo pipefail

app="$1"
expected_build="$2"
mode="${3:-}"

fail() {
  echo "::error::$1"
  exit 1
}

[ -d "$app" ] || fail "No app bundle at $app. If this is an archive, it may have become a generic archive (check SKIP_INSTALL on the extensions)."

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null; }

group="$(plist "$app" CMXAppGroupID)" || fail "The app's Info.plist has no CMXAppGroupID"
version="$(plist "$app" CFBundleShortVersionString)"
build="$(plist "$app" CFBundleVersion)"
bundle_id="$(plist "$app" CFBundleIdentifier)"
[ "$build" = "$expected_build" ] || fail "The app's build number is $build, expected $expected_build"

entitlements_of() {
  local binary_bundle="$1"
  local out
  out="$(mktemp)"
  if ! codesign -d --entitlements - --xml "$binary_bundle" > "$out" 2>/dev/null || [ ! -s "$out" ]; then
    codesign -d --entitlements :- "$binary_bundle" > "$out" 2>/dev/null || true
  fi
  echo "$out"
}

check_bundle() {
  local bundle="$1"
  local name
  name="$(basename "$bundle")"
  local ents
  ents="$(entitlements_of "$bundle")"
  [ -s "$ents" ] || fail "$name has no entitlements in its signature"

  local family
  family="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.family-controls' "$ents" 2>/dev/null || true)"
  [ "$family" = "true" ] || fail "$name is not signed with com.apple.developer.family-controls"

  local groups
  groups="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$ents" 2>/dev/null || true)"
  echo "$groups" | grep -q "$group" || fail "$name is not signed with the App Group $group"

  if [ "$mode" = "distribution" ]; then
    local task_allow beta
    task_allow="$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$ents" 2>/dev/null || echo false)"
    [ "$task_allow" = "false" ] || fail "$name still has get-task-allow (not an App Store signature)"
    beta="$(/usr/libexec/PlistBuddy -c 'Print :beta-reports-active' "$ents" 2>/dev/null || echo missing)"
    [ "$beta" = "true" ] || fail "$name has no beta-reports-active entitlement (not signed for TestFlight)"
  fi
  rm -f "$ents"
  echo "  $name: entitlements OK"
}

echo "App $bundle_id $version ($build), App Group $group"
check_bundle "$app"

for ext in CMXMonitor CMXShieldConfig CMXShieldAction; do
  appex="$app/PlugIns/$ext.appex"
  [ -d "$appex" ] || fail "$ext.appex is not embedded in the app"
  ext_id="$(plist "$appex" CFBundleIdentifier)"
  case "$ext_id" in
    "$bundle_id".*) ;;
    *) fail "$ext.appex has bundle ID $ext_id, which does not start with $bundle_id." ;;
  esac
  [ "$(plist "$appex" CFBundleShortVersionString)" = "$version" ] || fail "$ext.appex has a different version"
  [ "$(plist "$appex" CFBundleVersion)" = "$build" ] || fail "$ext.appex has a different build number"
  [ "$(plist "$appex" CMXAppGroupID)" = "$group" ] || fail "$ext.appex has a different App Group in its Info.plist"
  echo "  $ext ($ext_id): $(plist "$appex" NSExtension:NSExtensionPointIdentifier)"
  check_bundle "$appex"
done

api="$(plist "$app" CMXAPIBaseURL || true)"
if [ -n "$api" ]; then
  echo "Account server: set (accounts live on the server)"
else
  echo "Account server: not set (device-only accounts; set the repository variable API_BASE_URL to change this)"
fi
echo "Bundle check passed."
