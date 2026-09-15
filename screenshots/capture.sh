#!/usr/bin/env bash
#
# App Store screenshot capture. RUNS ON THE MAC (needs simctl + a simulator).
#
#   cd ~/Chirp && bash screenshots/capture.sh          # all six shots
#   cd ~/Chirp && bash screenshots/capture.sh 05Map    # one, by test-method suffix
#
# ScreenshotTests referenced this script by name for months without it ever
# being committed, so a recapture meant reconstructing the simulator setup from
# the test's doc comment. It is the setup, not the test, that is easy to get
# wrong: an ungranted location permission or a missing simulated fix produces a
# map shot with no blue dot and no check-in state, which looks like a capture
# that merely rendered badly.
#
# Raw PNGs land in /tmp/chirp-shots on the Mac; copy them to screenshots/raw/
# and run appstore_compose.py to build the branded set.
set -euo pipefail

SIM_NAME="${SIM_NAME:-iPhone 16 Pro Max}"
SCHEME="ChirpDeviceTests"          # the scheme that contains ChirpUITests
ONLY="${1:-}"
OUT="/tmp/chirp-shots"

say() { printf '\033[1;36m▸\033[0m %s\n' "$*"; }

udid=$(xcrun simctl list devices available \
  | awk -v n="$SIM_NAME" -F'[()]' '$0 ~ n"[[:space:]]*\\(" {print $2; exit}')
[ -n "$udid" ] || { echo "no available simulator named '$SIM_NAME'"; exit 1; }
say "simulator $SIM_NAME ($udid)"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

# 9:41, full bars, full battery — the App Store convention, and it keeps the
# set from advertising the capture date in the corner of every image.
say "pinning status bar"
xcrun simctl status_bar "$udid" override \
  --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode notSupported \
  --batteryState charged --batteryLevel 100

BUNDLE_ID="com.jacksonmsanger.chirpchirp"
say "granting location to $BUNDLE_ID"
xcrun simctl privacy "$udid" grant location "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl privacy "$udid" grant microphone "$BUNDLE_ID" 2>/dev/null || true

# The map shot needs a fix, and it has to be the CENTROID OF THE SEEDED PEERS
# in ScreenshotSeed.swift (Yosemite Valley, ~37.745,-119.595). The map opens
# centred on the user's own position, so a fix anywhere else leaves every peer
# pin hundreds of miles off-screen and yields a map shot with nothing on it.
say "setting simulated location"
xcrun simctl location "$udid" set 37.7452,-119.5947 2>/dev/null || true

rm -rf "$OUT"; mkdir -p "$OUT"

args=(-scheme "$SCHEME" -destination "id=$udid" -quiet)
if [ -n "$ONLY" ]; then
  args+=(-only-testing:"ChirpUITests/ScreenshotTests/test${ONLY}")
  say "capturing test${ONLY}"
else
  args+=(-only-testing:ChirpUITests/ScreenshotTests)
  say "capturing all shots"
fi

xcodebuild test "${args[@]}"

say "raw captures in $OUT:"
ls -la "$OUT"
