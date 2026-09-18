#!/bin/bash
# [MAC] Speak every clip in clips.tsv with macOS `say`.
#
#   bash scripts/demo-audio/say-clips.sh <outdir>
#
# Writes, per clip id:
#   <id>.wav  16 kHz mono 16-bit PCM: input to encode_opus_frames.py (VPS),
#             which produces the app's Opus frame format
#   <id>.m4a  AAC, 16 kHz mono, 32 kbps: the exact settings VoiceNoteRecorder
#             records with, because chat voice notes play through AVAudioPlayer
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:?usage: say-clips.sh <outdir>}"
mkdir -p "$out"
grep -v '^#' "$here/clips.tsv" | while IFS=$'\t' read -r id voice text; do
  [ -n "$id" ] || continue
  say -v "$voice" -r 175 --file-format=WAVE --data-format=LEI16@16000 -o "$out/$id.wav" "$text"
  afconvert -f m4af -d aac@16000 -c 1 -b 32000 "$out/$id.wav" "$out/$id.m4a"
  echo "$id $(stat -f %z "$out/$id.wav")B wav, $(stat -f %z "$out/$id.m4a")B m4a"
done
