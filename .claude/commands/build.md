# build — build Chirp iOS app

## Target: $ARGUMENTS (default: build)

1. Push code to Mac: `xpush`
2. Build:
   - `build` → `xpush build`
   - `run` → `xpush run` (build + launch in simulator)
   - `open` → `xpush open` (open in Xcode)
3. If build fails, parse errors and fix them. Rebuild up to 5 times.
4. If target was `run`, screenshot the simulator: `mac screenshot sim`

## Notes:
- Chirp is a Nextel-style push-to-talk walkie-talkie app.
- Uses CoreBluetooth (BLE) for proximity-based communication.
- BLE features won't work in simulator — test UI only, flag BLE-dependent flows.
