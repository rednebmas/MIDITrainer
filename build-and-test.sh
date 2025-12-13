#!/bin/bash

# this is really slow, so it's not very useful for local development

set -euo pipefail

read -r UDID NAME RUNTIME < <(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
for rt, devs in d.items():
    for dev in devs:
        if dev.get("isAvailable") and dev["name"].startswith("iPhone"):
            print(dev["udid"], dev["name"], rt)
            sys.exit(0)
raise SystemExit("No available iPhone simulators found")
')

echo "Using simulator: $NAME ($RUNTIME) [$UDID]"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcodebuild -project ./MIDITrainer.xcodeproj -scheme MIDITrainer -sdk iphonesimulator -destination "id=$UDID" test
