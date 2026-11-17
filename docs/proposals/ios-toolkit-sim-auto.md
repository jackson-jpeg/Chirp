# Proposal for ios-toolkit: let `auto` find a project's own simulator

Not a change to this repo. For whoever owns `/root/ios-toolkit` (Jackson's call to apply).

**Applied 2026-11-17** by the SoGoJet session (owner of ios-toolkit), ios-toolkit `3ae155c`, on
Jackson's word via Sessions: `auto` now prefers a device named "<registry key> ...", booted
first; tests `tests/sim-resolve.test.sh`.

## The problem

`bin/ios`, `sim_resolver()` (around line 333): with `IOS_SIM_DEVICE` unset the simulator is
`auto`, which takes the first booted device whose name starts with `iPhone`, else the first
available one starting with `iPhone`. The sed pattern is anchored: `^ *iPhone[^(]*(UDID)`.

Every project now names its one simulator `<Project> iPhone <model>` (the one-simulator-per-
project rule), for example `CreaseCracker iPhone 17 Pro`. None of those start with `iPhone`, so
`auto` matches nothing and `ios build` / `ios test` stop with "no available iOS simulator
matching 'auto'". Projects work around it today by exporting `IOS_SIM_DEVICE` by hand
(CreaseCracker's CLAUDE.md does). If `auto` were loosened to match `iPhone` anywhere, it would
pick another project's simulator, which is worse.

## Proposed fix

1. An optional `simulator:` key per app in `config/projects.yml`, for example
   `simulator: "Chirp iPhone 17 Pro"`, read where `IOS_SIM_DEVICE` defaults (`cmd_build`,
   `cmd_run`, `cmd_test`: `local sim="${IOS_SIM_DEVICE:-${registry_sim:-auto}}"`).
2. In `auto`, before the bare `iPhone` patterns, prefer a device whose name starts with the
   app's display name (the registry key, case-insensitive), booted first, then available.
3. The error message names the expected `<Project> iPhone ...` name rather than only
   "create one in Xcode".

Order of precedence: `IOS_SIM_DEVICE`, then the registry's `simulator:`, then `auto`.
`auto` stays deterministic and never picks another project's device unless the name has no
project prefix at all (the old `iPhone 16 Pro` style), which keeps today's behaviour for
those.

## Tests

`vps-tools/tests/` has no test of `sim_resolver`. A small one could feed canned
`simctl list devices available` text to the prelude's resolution block (extracted to a
function) and assert the UDID chosen for: a project-named device, a bare `iPhone` device,
both present, booted versus not, and none.

## Why Chirp cares

Chirp has no simulator yet (Inbox item `chirp-2-0-jackson`). When it gets one it will be
named `Chirp iPhone 17 Pro`, and `ios test` will not find it under `auto`.
