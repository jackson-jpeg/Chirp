# Build Rules

You are on a Linux VPS. You CANNOT run swift, xcodebuild, or xcrun directly.

- Build: `ios build` (auto-detects the app from cwd)
- Build + run in simulator: `ios run`
- Install on physical iPhone: `ios install`
- Screenshot simulator: `mac screenshot sim`
- Full sync to Mac: `san sync <project>` (usually not needed — the autosync
  hook pushes every Edit/Write, and `ios` rsyncs before building)

Files auto-sync to the Mac when you Edit/Write them (`.macsync` marker projects).
The Mac is build-only — never edit files there; the VPS is the source of truth.

Error paths map: `/Users/jackson/Chirp/` → `/root/Chirp/`

Note: CoreBluetooth (BLE) features don't work in the simulator. Test UI only —
flag BLE-dependent flows that can't be verified visually.
