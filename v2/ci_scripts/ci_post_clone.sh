#!/bin/bash
# Xcode Cloud, after the clone: install XcodeGen (pinned, the Mac's version) and
# generate v2/ChirpChirps.xcodeproj, which is not in git. Xcode Cloud finds this
# folder beside the project (v2/). Never runs locally. Modelled on LeftSaid's.
# v2/project.yml already signs automatically (what Xcode Cloud needs), so unlike
# LeftSaid nothing is rewritten.
set -euo pipefail
XCODEGEN_VERSION=2.45.3
cd "$CI_PRIMARY_REPOSITORY_PATH/v2"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
unzip -q "$tmp/xcodegen.zip" -d "$tmp"
XG="$tmp/xcodegen/bin/xcodegen"
"$XG" --version
"$XG" generate --quiet
ls ChirpChirps.xcodeproj/xcshareddata/xcschemes
