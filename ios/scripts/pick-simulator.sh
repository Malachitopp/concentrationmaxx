#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the newest iOS runtime that the
# selected Xcode can run (runtime version <= the simulator SDK version).
# Device names change with every Xcode release, so CI never hard-codes one.
set -euo pipefail

sdk="$(xcrun --sdk iphonesimulator --show-sdk-version)"

xcrun simctl list devices available --json | python3 -c '
import json, re, sys

sdk = tuple(int(part) for part in sys.argv[1].split("."))
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    match = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    if version > sdk[:2]:
        continue
    for device in entries:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            candidates.append((version, device["name"], device["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator found for iOS SDK " + sys.argv[1])
candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
version, name, udid = candidates[0]
print("Using %s (iOS %d.%d) %s" % (name, version[0], version[1], udid), file=sys.stderr)
print(udid)
' "$sdk"
