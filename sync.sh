#!/bin/bash
# Sync Chirp source to Mac WITHOUT destroying Xcode project state
set -e

MAC="macbook"
LOCAL="/root/Chirp"
REMOTE="/Users/jackson/Chirp"

rsync -az --delete \
  --exclude='.git' \
  --exclude='*.xcodeproj' \
  --exclude='DerivedData' \
  --exclude='.DS_Store' \
  --exclude='.build' \
  --exclude='.swiftpm' \
  "$LOCAL/" "$MAC:$REMOTE/"

# Regenerate project and resolve packages in one shot
ssh "$MAC" "cd $REMOTE && /opt/homebrew/bin/xcodegen generate --spec project.yml 2>&1 | tail -1 && xcodebuild -project ChirpChirp.xcodeproj -scheme Chirp -resolvePackageDependencies 2>&1 | tail -3"

echo "Synced + packages resolved"
