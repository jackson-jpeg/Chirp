#!/usr/bin/env bash
# Compile the 2.0 app on the Mac for the generic iOS Simulator destination.
# Needs no simulator device (Chirp has none yet: Inbox chirp-2-0-jackson), so it
# proves the code compiles; it cannot run it or take screenshots (that is
# `ios run` once the simulator exists).
#
#   bash v2/scripts/mac-compile.sh            (run through heavy)
#
# Copies v2/ to ~/Chirp-v2-ui on the Mac (a scratch dir this tooling owns;
# delete it at session end), then one Mac tool per ssh call.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
dest="Chirp-v2-ui"
rsync -a --delete --exclude .build --exclude '*.xcodeproj' --exclude design "$here/" "macbook:$dest/"
ssh macbook-tunnel "cd ~/$dest && /opt/homebrew/bin/xcodegen generate --quiet"
ssh macbook-tunnel "cd ~/$dest && xcodebuild -project ChirpChirps.xcodeproj -scheme Chirp -destination 'generic/platform=iOS Simulator' -derivedDataPath ~/$dest/.dd CODE_SIGNING_ALLOWED=NO -quiet build > ~/$dest/build.log 2>&1; s=\$?; grep -E 'error:' ~/$dest/build.log | sort -u | head -60; exit \$s"
echo "compiled"
