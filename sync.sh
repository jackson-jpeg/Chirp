#!/bin/bash
# Sync Chirp source to Mac WITHOUT destroying Xcode project state
set -e
source /root/vps-tools/lib/remote.sh   # ssh exit codes are not usable — see remote.sh

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

# Regenerate project and resolve packages in one shot.
#
# The old one-liner printed "Synced + packages resolved" unconditionally: the
# ssh exit status is discarded by Tailscale (tailscale/tailscale#18256), and
# both remote commands were piped into `tail`, so even locally the status would
# have been tail's. remote() runs the script under `set -eo pipefail` and gates
# on a stdout sentinel, so the success line below is now earned.
remote /tmp/chirp-sync.log "$MAC" "
  cd '$REMOTE'
  /opt/homebrew/bin/xcodegen generate --spec project.yml
  test -d '$REMOTE/ChirpChirp.xcodeproj'
  xcodebuild -project ChirpChirp.xcodeproj -scheme Chirp -resolvePackageDependencies
" || remote_die /tmp/chirp-sync.log "xcodegen / package resolution failed for Chirp"

tail -3 /tmp/chirp-sync.log
echo "Synced + packages resolved"
