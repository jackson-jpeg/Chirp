# Xcode Cloud for ChirpChirps 2.0

Started 2026-11-17 under Jackson's Mac disk policy (`CLAUDE.md`): Xcode Cloud first for builds
and simulator tests, the Mac as the fallback. Free tier only, never upgrade. The 25 compute
hours a month (they reset on the 2nd) are shared by all of Jackson's apps. Workflows start by
hand only, never on a push. Xcode Cloud email is already off for the account (2026-10-20).

Ported from LeftSaid's setup (`/root/LeftSaid/docs/rebuild/xcode-cloud.md`).

## In git

- `v2/ci_scripts/ci_post_clone.sh` (beside the generated `v2/ChirpChirps.xcodeproj`, where Xcode
  Cloud looks): installs XcodeGen 2.45.3 (the Mac's version, checked 2026-11-17) and runs
  `xcodegen generate` in `v2/`. v2 already signs automatically, so unlike LeftSaid nothing is
  rewritten.
- `scripts/asc/xcode_cloud.py` (runs on the VPS; each API call runs `scripts/asc/asc-api.rb` on
  the Mac, so the key never leaves it):
  - `status`: product, repository, workflows, and this month's hours (Chirp and all apps).
  - `setup [--dry-run]`: makes "TestFlight" (archive scheme Chirp, App Store eligible; nothing
    submits) and "Tests" (the Chirp scheme's tests, which are ChirpCoreTests and ChirpUITests,
    on iPhone 17 Pro Max, newest runtime), with manual start on `master` only and every
    automatic start off. It disables any other workflow (onboarding's Default starts on every
    push), then reads them back.
  - `start testflight|tests [--branch master]`: prints the hours used and left first, and
    refuses at 20 h counted across Chirp's, LeftSaid's, Sim Sunday's and Crease Cracker's logs.
  - `hours`: logs each finished run to `docs/xcode-cloud-hours.tsv`.
  - The Xcode version is `Xcode 27.1` by default, to match the Mac after its update. Use
    `XCODE_CLOUD_XCODE="Xcode …"` for another; a name Xcode Cloud doesn't offer fails and
    lists the ones it does.
  - It refuses any write to a submission endpoint.

## Status (2026-11-17)

- `status` ran: **no Xcode Cloud product for ChirpChirps** (app 6761436901). 2.54 of 25 hours
  logged this month across all apps.
- Nothing is set up until Jackson's click below, and that waits for the Mac's Xcode 27 update.
- **Note on cost:** "Tests" runs ChirpUITests too, including `BuildVsDesignTests` (20 app
  launches). If that costs too many minutes, split it out with a test plan.

## Jackson's clicks (the API can't do these)

1. **Create the product** once the Mac is back on Xcode 27. In Finder on the Mac, open
   `~/Chirp/v2/ChirpChirps.xcodeproj` (`~/Chirp` is a git clone; if the `.xcodeproj` is missing,
   a session runs `ios build chirp` first to generate it). In Xcode: **Integrate → Create
   Workflow… → ChirpChirps → Next → Grant Access**. On GitHub, add **`jackson-jpeg/Chirp`** to
   the Xcode Cloud app's repository access (GitHub → Settings → Applications → Xcode Cloud →
   Configure → Repository access → Save). Back in Xcode, **Complete**. Don't press **Start
   Build**; close it.
   - **Watch for this:** on 2026-11-16, Create Workflow for Crease Cracker *reused* LeftSaid's
     product and relinked it. Make sure Xcode is creating a **new** product named for
     ChirpChirps, not picking an existing one. After the click, a session runs `status` to
     confirm the product belongs to app 6761436901, then `setup`.
2. **Next build number** (only before the first TestFlight run from Xcode Cloud): App Store
   Connect → Xcode Cloud → ChirpChirps → Settings → Build Number → set it above the newest
   ChirpChirps build.
