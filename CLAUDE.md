# ChirpChirps (Chirp)

Project rules for this repo. The box-wide rules are in `/root/CLAUDE.md`; this file adds
Chirp's own. `.claude/rules/ios-build.md` covers the `ios` commands.

## Mac disk policy (Jackson, 2026-11-17, standing rule; relayed by the lead, word for word)

> MAC DISK POLICY, decided by Jackson tonight (the Mac hit under 1 GB free because nobody
> owned the whole disk):
> 1. Xcode Cloud FIRST for builds and simulator tests (25 free hours/month, never pay; fall
> back to the Mac if hours run out). The Mac is the fallback plus Jackson's plugged-in iPhone.
> 2. Exactly 4 SHARED simulators on the Mac, newest runtime only: "Shared iPhone Pro Max A",
> "Shared iPhone Pro Max B" (newest Pro Max), "Shared iPhone Duo", "Shared iPad". Sessions
> take turns via the mac-sim lock. No session ever creates its own simulator. After each job:
> uninstall the job's app and erase what grows (app data, logs, crash reports), but keep the
> devices and runtime.
> 3. One runtime and one Xcode at a time; delete the old one once the new one works.
> 4. Free-space floors checked by the foreman before every Mac job: soft 25 GB = run the
> cleanup sweep first, then start; hard 5 GB = no Mac job starts, sweep, and if still under,
> inbox the lead.
> 5. Repo copies on the Mac: keep while still on the same version, delete when the session
> starts the next version.
> 6. DerivedData: kept while a version is in progress, cleared when it ships or the
> branch/worktree is gone, global cap 5 GB oldest first.
> 7. Weekly foreman sweep: Homebrew cache, old DerivedData, simulator logs and crash reports,
> orphan simulators/runtimes, stale repo copies, build artifacts in ~/Downloads. One line to
> the lead: free before and after.
> 8. sang3r Today shows Mac free disk with the floor lines.

**What it means for Chirp:**

- **Builds and simulator tests go to Xcode Cloud first:** `scripts/asc/xcode_cloud.py
  start tests` (ChirpCore and UI tests) and `start testflight` (archive). Every start prints
  the hours used across all apps, and refuses at 20 h without Jackson's okay. Log each
  finished run with `scripts/asc/xcode_cloud.py hours`. The setup and Jackson's one-time
  clicks are in `docs/xcode-cloud.md`.
- **The Mac is the fallback** (`ios build`, `ios test`, under `mac-sim`) when hours run out
  or Xcode Cloud can't run the job. The Mac is also still needed for jobs on Jackson's
  plugged-in iPhone (the App Review screen recording, `ios install`) and for anything that
  needs two real phones (Bluetooth, Find, BACKGROUND.md B1 to B5).
- **No Chirp simulator.** "Chirp iPhone 17 Pro" is gone (deleted 2026-11-17) and is never
  recreated. On the Mac, use a shared simulator under `mac-sim` (`IOS_SIM_DEVICE="Shared
  iPhone Pro Max A"` or whichever is free), and after the job uninstall
  `com.jacksonmsanger.chirpchirp` and erase what grows. This overrides the older "one
  simulator per project" line in `~/.claude/CLAUDE.md`, and every mention of the Chirp
  simulator in `docs/NEXT.md` and the handoffs.
- **Result bundles** (`*.xcresult`) on the Mac are deleted as soon as they are read.

## User-facing copy

No em dashes in anything a user reads (`/root/CLAUDE.md`). `site-deploy/deploy.sh` refuses
them on chirpchirps.com; `v2/App/UITests/DemoModeTests.swift` holds the demo copy to it.

## App Store

No submission until `python3 /root/ios-toolkit/lib/app_review_check.py /root/Chirp/v2`
passes on `docs/app-review/<version>.md` (HARD RULE in `docs/NEXT.md`).

## Xcode tools over MCP (2026-11-18, the lead)

Xcode 27 serves its own tools to agents: `xcrun mcpbridge`, wired user-wide as
the MCP server `xcode` (`ssh macbook-tunnel xcrun mcpbridge`; the older
xcodebuildmcp is kept as `xcodebuildmcp`). It can build, run all or some tests,
render SwiftUI previews, run on a simulator or a device, read build logs and
crash and performance reports from Xcode Organizer, and edit the project
(targets, build settings, entitlements, Info.plist, string catalogs).

- It works only on a project that is open in Xcode: call `XcodeOpenWorkspace`
  with the Mac path (`/Users/jackson/<repo>/...xcodeproj`) first. The first
  open by a new agent asks Jackson to approve it in Xcode's MCP menu.
- The Mac rules still hold: run tests and anything that boots a simulator
  under `mac-sim` (`hub-lock mac-sim -- ...`, or use `ios test`/`ios run`,
  which take it), only on the four shared simulators ("Shared iPhone Pro Max
  A", "Shared iPhone Pro Max B", "Shared iPhone Duo", "Shared iPad"). Never
  create a simulator. Xcode Cloud first for builds and tests when it is set up.
- The VPS stays the source of truth: edit files here, never through Xcode's
  write tools; the Mac copy is replaced on every sync.
