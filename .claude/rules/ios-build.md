---
description: iOS build rules — dual-machine VPS/Mac setup. BLE won't work in simulator.
globs: ["**/*.swift"]
---

# Build Rules

You are on a Linux VPS. You CANNOT run swift, xcodebuild, or xcrun directly.

- Build: `xpush build`
- Build + run: `xpush run`
- Screenshot simulator: `mac screenshot sim`

Files auto-sync to Mac when you Edit/Write them. xpush also syncs via git.

Note: CoreBluetooth (BLE) features don't work in the simulator. Test UI only — flag BLE-dependent flows that can't be verified visually.
