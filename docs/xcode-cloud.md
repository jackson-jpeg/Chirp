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
- Nothing is set up until the Create Workflow clicks below. The lead does them by computer use after the Mac's Xcode 27 install (Jackson, Inbox `chirp-xcode-cloud`).
- **Note on cost:** "Tests" runs ChirpUITests too, including `BuildVsDesignTests` (20 app
  launches). If that costs too many minutes, split it out with a test plan.

## Create Workflow: exact steps (the lead, by computer use on the Mac; Jackson's decision 2026-11-17)

Jackson (Inbox `chirp-xcode-cloud`, lead decision): after the macOS and Xcode 27 install, the
lead does these clicks on the Mac with computer use, one app after another. The API can't
create a product. Names to expect:

| What | Value |
|------|-------|
| Project to open | `~/Chirp/v2/ChirpChirps.xcodeproj` (XcodeGen project `ChirpChirps`, not in git) |
| App target and **scheme** | **`Chirp`** (the scheme and the product Xcode lists are both "Chirp", not ChirpChirps) |
| Other targets (not products) | `ChirpLive` (widget extension, embedded), `ChirpUITests`, package `ChirpCore` |
| Bundle ID | `com.jacksonmsanger.chirpchirp` |
| App Store Connect app | **ChirpChirps**, Apple ID **6761436901** (it already exists: pick it, never create one) |
| Team | 2MU4PC84GZ |
| GitHub repository | **`jackson-jpeg/Chirp`**, branch **`master`** |

**Before the clicks (from the VPS, once the hold is lifted):**
1. `san sync chirp`, so the Mac's `~/Chirp` matches master.
2. If `~/Chirp/v2/ChirpChirps.xcodeproj` is missing: `ssh macbook-tunnel "cd ~/Chirp/v2 && /opt/homebrew/bin/xcodegen generate"`.
3. `ssh macbook "git -C ~/Chirp remote get-url origin"` must print the GitHub URL of `jackson-jpeg/Chirp`. Xcode refuses Create Workflow in a folder that isn't a git clone, which LeftSaid hit. `~/Chirp/.git` existed on 2026-11-17.

**The clicks:**
1. In Finder, open `~/Chirp/v2/ChirpChirps.xcodeproj` in Xcode 27. Wait for package resolution to finish.
2. Menu **Integrate → Create Workflow…**
3. "Select a product": choose **Chirp** (the app). Next.
4. Workflow review (Xcode's "Default"): leave it as it is, Next. `setup` disables it later.
5. "Grant access to your source code": **Grant Access**. On GitHub, in the Xcode Cloud app's
   repository access (Settings → Applications → Xcode Cloud → Configure → Repository access),
   add **`jackson-jpeg/Chirp`** and Save. The app was installed for other repos only.
   Back in Xcode, it should show the repository as connected.
6. "App Store Connect app": choose the **existing** app **ChirpChirps** (6761436901,
   `com.jacksonmsanger.chirpchirp`). Never "create a new app".
7. **Complete.** Do **not** press **Start Build** at the end; close the sheet. A Default run
   would start right away and spend the shared hours.
8. **Check:** if any step offers a product named after another app (LeftSaid, CreaseCracker,
   SimSunday), stop. On 2026-11-16, Crease Cracker's Create Workflow reused LeftSaid's
   product and relinked it.

**After the clicks (Chirp's session, from the VPS):**
1. `python3 scripts/asc/xcode_cloud.py status`: the product must be new and belong to app
   6761436901, with repository `Chirp`.
2. `python3 scripts/asc/xcode_cloud.py setup --dry-run`, then `setup`: makes "Tests" and
   "TestFlight" (scheme `Chirp`, container `v2/ChirpChirps.xcodeproj`, manual start on master
   only) and disables Default. If `Xcode 27.1` isn't offered, it lists the names that are; set
   `XCODE_CLOUD_XCODE`.
3. `python3 scripts/asc/xcode_cloud.py start tests`, then `hours` once it finishes.

## Before the first TestFlight run from Xcode Cloud

**Next build number:** App Store Connect → Xcode Cloud → ChirpChirps → Settings → Build Number
→ set it above the newest ChirpChirps build.
