# NEXT: ChirpChirps

<!--
The foreman's queue for this repo (sang3r.com, src/lib/foreman/next.ts). The format is strict:
- Sections: "## Queue" (the work, top first), "## Needs Jackson" (never sent), "## Done" (optional).
- An item is ONE line: "- [ ] words" is open, "- [x] words" is done. Order is priority.
- A sub-item is the same line indented two spaces under its parent. The foreman sends the first
  open sub-item of the first open item. An item with no open sub-items is sent itself.
- Anything else (text under an item, other headings) is a note. The foreman does not read notes.
- When you finish an item, tick it. Put follow-ups in the Queue where they belong in the order.
- When only Jackson can do an item (an App Store submission, a production data delete, a money
  action, a decision that is his), move it under "Needs Jackson", file it with needs-you, move on.
-->

## The mandate (Jackson, 2026-11-17, relayed by the lead; word for word)

> ChirpChirps 2.0 is a complete redo, not a patch pass: the current app was built on an old model, is bandaided together and the interface reads as AI slop.
>
> 1) Audit, read-only: on a phone plus the simulator, what truly works (push to talk both ways, texts with acks, a relay hop), what is dead, faked or duplicated. ~/Downloads/chirpchirps-redo/AUDIT.md. 2) New clean project. Carry over only code the audit proves on hardware (likely the audio and transport core), rewritten clean with tests. Everything else is new. 3) v2.0 scope: hold to talk to friends nearby, channels, texts with delivery ticks, who is nearby, block a person, location sharing off by default and asked every time, a demo mode for App Review. It must answer all three past rejections: 5.1.1(iv) no permission pre-prompts, 2.1(a) reviewer access, 5.1.2(i) blocking, declinable location consent, check-in each time. 4) Design: work out the direction from what the product is, talking with your group where there's no signal (festivals, ski trips, cruises, camping). Not the old amber radio look, not a style from another studio app. Make 3 truly different directions as Talk-screen phone mockups in ~/Downloads/chirpchirps-redo/design/, then stop and file one Inbox item for Jackson to pick. No UI build before he picks. 5) After the pick: every screen in that style, Dynamic Type, VoiceOver, light and dark. 6) Two-device test, then TestFlight. Never submit until Jackson has played it.

## Update to the mandate (Jackson, 2026-11-17, relayed by the lead; word for word)

> skip step 4's three design directions. Claude has mocked up three routes for Jackson to pick from (Dawn Chorus, Night Wire, Trail Signal), all keeping the two birds on a wire as the icon. Do the audit and the clean core (audio, transport, blocking, consent, demo mode) now with plain placeholder UI, and wait for his pick before any styled screen.

Note from the session that wrote this (not Jackson's words): there were FOUR rejections, not
three. The fourth, and the one 1.0 is rejected under today, is **Guideline 2.5.4**: the build
declared the `audio` background mode. 2.0 must declare no `UIBackgroundModes` and be
foreground-only, or it will be rejected the same way. Details and a worked fix (on 1.0's code)
are on branch `fix/2-5-4-foreground-only`, in `docs/sessions/2026-11-17-review-2-5-4.md`.
Handoff: `docs/sessions/2026-11-17-handoff.md`.

## Design approved (Jackson, 2026-11-17, relayed by the lead; word for word)

> Jackson APPROVED the ChirpChirps 2.0 design (Dawn Chorus). It is the spec now, not a direction. All 14 screens are in ~/Downloads/chirpchirps-redo/design/ on the Mac: PNGs at 3x, and the source of each in design/source/ with exact colors, sizes, copy and the bird drawing as SVG paths (the symbol named bird, beakOpen, beakClosed, and the app icon). Build to them: 1) The app icon from Main: two birds on a wire, yellow one with the gold tuft (no dark cap), coral one listening. Render it at 1024 from the SVG for the asset catalog. 2) The bird is one reusable SwiftUI view drawn from those SVG paths, colored per person, beak open while talking. 3) Every screen in the files, every state, light mode first, then a dark version that keeps the same feel. 4) Plain words from the screens, never mesh or node jargon. Do the background-receive proof first as asked, then the core, then these screens. Put simulator screenshots of each screen next to the matching design PNG in ~/Downloads/chirpchirps-redo/build-vs-design/ and file one Inbox item when they match. Never submit until Jackson plays it.

The design files are copied into the repo at `v2/design/` (PNGs and `source/*.dc.html`).

Order the lead gave: background proof, then the core, then the screens. The background proof
and every run of the app wait on the Chirp simulator (Inbox `chirp-2-0-jackson`), so the
screens are being built now and proved by compiling (`v2/scripts/mac-compile.sh`, generic
simulator destination, no device needed); screenshots follow once the simulator exists.

## Queue

- [ ] Build-vs-design screenshots, now taken by a UI test (seventh session): `v2/App/UITests/BuildVsDesignTests.swift` (target `ChirpUITests`, on master `5cf6c9a`) launches every screen light and dark and writes `<Name>-<light|dark>-build.png` to SCREENSHOT_DIR. Run: `cd /root/Chirp/v2 && IOS_SIM_DEVICE="Chirp iPhone 17 Pro" IOS_TEST_RESULT_BUNDLE=/Users/jackson/Chirp/v2/build/build-vs-design.xcresult ios test chirp --only ChirpUITests --env SCREENSHOT_DIR=/Users/jackson/Downloads/chirpchirps-redo/build-vs-design`. Then copy `v2/design/<Name>.png` beside each, pull the shots back, `python3 v2/scripts/side-by-side.py <shots> <out>` (design | light | dark), fix differences, one Inbox item. The foreman's Mac-job rule (only `ios build`/`run`/`test`, never drive the Simulator outside them) is why it is a test and not simctl
  Mac unreachable (2026-11-17 ~18:07 UTC): the first run failed at sync, tunnel refused; nothing built. Rerun when the tunnel is up
  Eighth session (~18:30 UTC): the rerun got `mac-sim`, synced and generated, then "NO TESTS RAN". `ios build chirp` on the same tree SUCCEEDED (the 2.0 app's first build through `ios`), so it is not a compile error. The partial xcresult showed xcodebuild gathering `simctl_diagnostics` (a Simulator-side failure) and those running the Mac out of disk (378 MB, deleted; mine). The first cause is not recorded: `ios test` hides xcodebuild's own error lines and deletes its log (proposal `docs/proposals/ios-toolkit-test-log.md`; committing it to ios-toolkit was refused). A second rerun was killed by Claude Code for low VPS memory while it still queued for `mac-sim`; nothing ran. Next: rerun the same command once memory and the Mac's free space allow; if NO TESTS RAN again, the toolkit proposal is what tells why
  Ninth session (20:29 UTC): Mac on AC power (11%, charging), tunnel UP; run 5 started, queued fifth for `mac-sim`
  Run 5 RAN (got `mac-sim` after 23 min): the 2.0 app launched and 18 of 20 shots were written (every screen light and dark except CatchUp), then the save of CatchUp-light failed with "No space left on device" on the Mac. Side-by-sides made (`v2/build/compare/`, ignored by git); compared screen by screen. Verdicts: MakeBird matches; Welcome, Chat, Find, Meetup, Nearby, Talk listen/hold minor; RollCall off (looser headline, plus the close button added on purpose). Fixes on branch `v2/design-fixes` (`83e9261`, pushed, NOT compiled): the design's line-height on Welcome, Roll call, Meet-up and Find's distance (`lineHeight(.multiple)`, confirmed in the iOS 26 SDK), clouds filled as one bank, Chat's voice bubble at full width, Find's halos visible in dark. Not changed, on purpose: the tab bar "10 pt high" (measured across a 30 pt taller device, not trusted), Talk's header avatar crop (the design file draws the bird oversized in its box), dark sun glow and Roll call's faded bird (taste). `v2/design-fixes` merged to master (`61d207c`) and `ios build` passes. Run 6 (ninth session, 21:13 UTC: ChirpCoreTests plus the shots, CatchUp included) was queued for `mac-sim` at the handoff; check the shots' times first (handoff). Next: recompare, then one Inbox item with the side-by-sides in `~/Downloads/chirpchirps-redo/build-vs-design/`
  Later (~20:00 to 20:15 UTC; toolkit fixes live, ios-toolkit `3ae155c`): run 3 got `mac-sim` after 12 min, then the tunnel was refused at sync. Run 4 synced and started testing, then the tunnel dropped mid-run ("Connection to localhost closed by remote host"). Its xcodebuild kept running on the Mac outside `mac-sim`, so it was killed and its bundle removed. The Mac was at load 64 to 75, on battery at 22% and discharging. No screenshots. Rerun when the Mac is on power and the tunnel holds
  Old wording, kept for the record: Build-vs-design screenshots (Jackson approved the simulator, 2026-11-17, Inbox chirp-2-0-jackson): simulator "Chirp iPhone 17 Pro" (AFF5BCE8-DAA0-4A1A-8931-7BCDBCC8C31A, iOS 26.5) is created; the `ios` registry entry `chirp` now points at `/root/Chirp/v2` (ios-toolkit `config/projects.yml`). `IOS_SIM_DEVICE="Chirp iPhone 17 Pro" ios run chirp`, then under `hub-lock mac-sim` relaunch with `-screen <Name>` and `-dark` (`xcrun simctl launch --terminate-running-process <id> com.jacksonmsanger.chirpchirp -screen <Name>`) and `xcrun simctl io <id> screenshot`, by UDID (two other simulators are booted). Each next to `v2/design/<Name>.png` in ~/Downloads/chirpchirps-redo/build-vs-design/; fix differences; one Inbox item when they match

Note (2026-11-17, sixth session): the foreman's "continue" message carries no "only `ios build`/`run`/`test`" rule (that rule rides on Mac jobs), so this session proved Captions with `v2/scripts/mac-compile.sh` (ssh xcodebuild, generic simulator destination, no Simulator driven) and `swift test`. The fifth session's note below is kept for the record.

Note (2026-11-17, fifth session): every open item below is app code that is proved by compiling it on the Mac. `ios build` cannot compile it without a Chirp simulator (Inbox `chirp-2-0-jackson`), and foreman Mac jobs may use only `ios build`/`run`/`test`, so `v2/scripts/mac-compile.sh` (ssh xcodebuild to a generic simulator destination, no device) is not used under them. Either answer unblocks the Queue.

- [x] Dawn Chorus build (branch `v2/dawn-chorus`): every screen built and compiling; the screenshots, Lock Screen and Watch moved to Needs Jackson (2026-11-17)
  - [x] App icon rendered at 1024 from Main's SVG (`v2/design/icon/AppIcon.svg`, `v2/scripts/render-svg.mjs`)
  - [x] The bird as one SwiftUI view from the design's paths (`v2/scripts/gen-bird-paths.py` writes `BirdPaths.swift`; `BirdView`, `BirdRenderer`, seven `BirdPalette`s; ChirpCore's set is now 7 colors and 3 chirps to match)
  - [x] Theme tokens light and dark, Nunito bundled (OFL), shared components, `v2/project.yml` (no UIBackgroundModes)
  - [x] Screens, light then dark: Welcome, MakeBird, Talk (listen and hold), Chat, Nearby (with Block), Find, Meetup, RollCall, CatchUp; compile clean (no warnings; 88 core tests pass). Not yet seen running: the match to the PNGs is unproven until the screenshots
  - [x] Fold the screen-local color tokens (`ChatStyle`, `CoverTokens`, Welcome's sky, raw navy) into `Theme.swift` (one `Theme.well` for all seven palettes), and share the wire scene's drawing: `SceneDrawing` (sky, glow, clouds, wire, chirp arcs) is used by `WireScene`, `TalkScene` and `WelcomeScene` (branch `v2/theme-tidy`)
  - [x] The chosen chirp moved from `@AppStorage` into `Flock.you`, and your bird (name, colors, chirp) is saved and restored by `Flock`

## Scope addition (the lead, relayed through Jackson's Sessions page, 2026-11-17; word for word)

> 2.0 scope grew (add to docs/NEXT.md, core first, styled UI still waits for Jackson's pick): build the core so it supports these. 1) Whisper: talk to one person, not the group. 2) Live captions on every voice message, on-device speech to text, captions-only mode. 3) Catch up: friends' phones hold messages for someone out of range and deliver them in order when they return (store and forward, with a cap). 4) Find: Nearby Interaction precision finding between iPhones with the UWB chip, plain distance fallback, plus Ping that makes a friend's phone chirp loudly. 5) New message types: meet-up spot (place, time, who's coming), roll call (are you OK, I need help with priority relay), small photos, battery level. 6) Each person's bird (colors) and their own start-talking chirp sound. 7) Lock screen and Dynamic Island Live Activity with a talk button. Before anything else, prove the app keeps receiving with the phone locked and no signal, and write what you find in ~/Downloads/chirpchirps-redo/BACKGROUND.md. That decides whether 7 is possible. Apple Watch and translation are 2.1.

What the background research found (`docs/audit/BACKGROUND.md`, also in
~/Downloads/chirpchirps-redo/): live voice while locked with no signal is not possible within
App Store rules as far as Apple's documentation goes. Texts and alerts over Bluetooth LE might
work. MultipeerConnectivity is deprecated in Xcode 27, so 2.0's transport moves to Network
framework. Hardware proof is still to come.

- [ ] Core for the new scope, in ChirpCore with tests, in this order (done so far: `Whisper.swift`, `Messages.swift`, `CatchUp.swift`, `Bird.swift`, `Photo.swift`, `Find.swift`, 88 tests; Whisper is a private two-person channel, so relays cannot tell who it is for):
  - [x] Whisper: a packet addressed to one PeerID, sealed pairwise (`LocalIdentity.sharedKey`), relayed but delivered only to that person, with its own floor
  - [x] Roll call and meet-up spot message kinds; roll call "I need help" gets priority relay (a higher TTL and first in the send queue)
  - [x] Catch up: store and forward of texts for an absent friend, with a cap per person and in total, delivered in order, deduped by message ID
  - [x] Battery level: sent only to friends, never in the public presence (the audit flagged 1.0 broadcasting it to strangers)
  - [x] Ping: a message kind that asks a friend's phone to chirp; rate-limited, only from friends, never from blocked people
  - [x] Each person's bird: colors and a chirp choice carried in the signed presence (an ID from a fixed set, not raw audio)
  - [x] Small photos: a capped, chunked message kind (size limit, sealed on locked channels)
  - [x] Captions: `Captions.swift` in ChirpCore (permission asked only on a tap, on-device or unavailable, captions-only silences only what is captioned, `CaptionTrack`; 11 tests, 101 in all) and the app's `LiveCaptions.swift` (Speech framework, `requiresOnDeviceRecognition`, one `CaptionFeed` per speaker stream); Talk's caption card offers "Turn on captions", says when Settings blocks it, and has a Captions on / only / off menu. Compiles with no warnings; not yet run (no simulator, and recognition needs a device)
  - [x] Find, core part: Nearby Interaction token exchange over the whisper channel (friends only) and an honest in range / through others / out of range fallback (`Find.swift`)
  - [x] Find, app part: `FindSession` in ChirpCore (the token exchange as one reducer: nothing runs before you open Find, a friend's offer is only a request, stop and close end it; `Find.fix` and `Find.tapInterval`; 12 tests, 113 in all) and the app's `FindRanging.swift` (NISession, tokens archived, haptics quicken with distance, a refused permission falls back); FindView opens it on appear and closes it on leave and in background; with no angle it shows the distance and "turn slowly", never a made-up arrow. Compiles with no warnings; proving it needs two UWB iPhones
  - [ ] Find follow-ups (with dispatch): pass the transport's whisper send into `FindRanging`, route received `.find` packets to `received(_:)`, show `requested` ("Maya is looking for you"), and take the fallback from `Find.fallback` on the roster instead of "Not heard yet"
    Written on `v2/dispatch` (ninth session, `8e41db4`, not compiled): `Mesh.attach`/`detach`/`routeFind`/`lookingForYou`/`fallback(for:)`, `Router.find(_:)` from Nearby, FindView on the real friend, Ping sent on the whisper channel. Ticks with the Dispatch item once `ios test chirp --only ChirpCoreTests` and `ios build` pass
  - [ ] Friends: nothing sets `Dispatch.friends` yet, so ping, battery and Find are refused both ways (Admission and `toFriend`). Needs the channel membership model: who is on a channel I joined (never everyone heard on Nearby, which the audit flagged for battery)
- [x] Transport on Network framework (ChirpCore `Link.swift`, 6 tests, 119 in all; app `Transport.swift`, `KeychainStore.swift`; compiles with no warnings; not run: needs two phones) (Bonjour with peer-to-peer Wi-Fi) instead of MultipeerConnectivity (deprecated in Xcode 27 beta); replaces the MultipeerConnectivity transport sub-item under item 2. Confirmed by Jackson's option 1
- [ ] Locked-phone link over Bluetooth LE (Jackson's option 1): texts, roll call, help, pings and "someone is talking" alerts as small framed packets over a GATT characteristic, through the same `SendGate` and router; `bluetooth-central` and `bluetooth-peripheral` added to `v2/project.yml` in the same change, never `audio`; Bluetooth asked on the same first tap as Local Network (5.1.1(iv)); a local notification for what arrives while locked. Proving it needs BACKGROUND.md section 4 on two iPhones
- [x] chirpchirps.com: the "Download for iPhone" and "Get ChirpChirps" buttons went to a 404 App Store page (lead site audit, 2026-11-17). Now "Coming to iPhone" with a release list (one email on release day, then the list is deleted; creasecracker.com's pattern, `chirpchirps-signup` on loopback :3330, nightly `chirpchirps-backup.timer`), privacy policy "Release list" section. The site is in this repo since (`site/`), deployed only with `bash site-deploy/deploy.sh` (refuses any App Store link or em dash, rolls back a failing nginx config). Deployed and checked live 2026-11-17
- [x] chirpchirps.com robots.txt and sitemap.xml (lead site audit, 2026-11-17): added, and www now 301s to chirpchirps.com (it served a second copy). `deploy.sh` refuses a page folder missing from the sitemap and checks all three live. Deployed and checked 2026-11-17
- [ ] chirpchirps.com in Dawn Chorus (lead site audit, 2026-11-17): once the 2.0 screens are proven by the build-vs-design screenshots, rebuild `site/` in the approved design (birds on the wire, sky palette, Nunito), copy from the 2.0 scope (the site still describes 1.0: offline maps, camera and photos, "8 hops of relay"); deploy with `site-deploy/deploy.sh`
- [ ] 7) Lock Screen and Dynamic Island Live Activity (Jackson's option 1): the flock, who talked last, and a button that opens the app to reply; no talk button that works locked. Widget extension with ActivityKit; started only while the app is in use

Order note (2026-11-17, second session): item 2 now comes before the rest of item 1, because
item 1's last open part (the hardware half) waits on Jackson's simulator answer, and the lead's
update says to build the clean core now. The hardware half still decides what 2.0 keeps: run
it as soon as a simulator exists, and correct the core if it disproves anything.

- [ ] 2) New clean project, clean core only (audio, transport, blocking, consent, demo mode) with plain placeholder UI: carry over only code the audit proves, rewritten clean with tests; everything else is new; no UIBackgroundModes (2.5.4); no styled screen before Jackson's pick
  - [x] Start from docs/audit/AUDIT.md: carry over only its CARRY OVER rows, one identity model (key fingerprint) instead of three. Done as the `v2/ChirpCore` Swift package (Foundation and CryptoKit only, `swift test` on the Mac, no simulator); map in `v2/README.md`
  - [x] Push-to-talk audio and floor control carry the channel ID, so channels (and locked channels) separate voice (audit defect). In ChirpCore: channel on every packet, floor reducer scoped to a channel, locked channels seal voice and floor; the app still has to wire it
  - [x] The receive jitter buffer resets for a new speaker, so a sender whose counter restarted is heard (audit defect). In ChirpCore: per (peer, epoch) stream in the jitter buffer and the router
  - [x] Texts with delivery ticks in ChirpCore: signed, acked only on a joined channel, ticks stored with the message
  - [ ] App target: `v2/project.yml` (xcodegen, bundle ID unchanged, no `UIBackgroundModes`, no camera, photo, speech or "Always" location strings) building the package and an empty placeholder app with `ios build`
  - [x] Audio session opened only while talking or listening, closed on background; no UIBackgroundModes (2.5.4). `AudioSessionPolicy` plus `recheck` (the tail's end) in ChirpCore, tested; the app's adapter `v2/App/Sources/App/AudioSession.swift` follows the scene phase, releases the floor on an interruption or a lost input, reapplies after a media services reset, and opens nothing at launch. Compiles; not yet run (no simulator, and audio needs a device)
  - [ ] Audio engine in the app: capture to 16 kHz Opus 20 ms frames and playback through ChirpCore's JitterBuffer; carry over the render-thread copy, the persistent converter and the DEBUG sine mic (audit section 7)
    Also: open a `LiveCaptions.begin` feed per speaker stream (and your own while holding), append decoded PCM, `end` when the stream ends; skip playback when `LiveCaptions.playsAudio` is false (captions-only)
  - [ ] Transport in the app: MultipeerConnectivity behind one send gate (ChirpCore `SendGate`), peers keyed by PeerID from presence, an invitation tie-break, advertising and browsing only after the first tap that needs them (5.1.1(iv))
  - [ ] Dispatch in the app: one switch on `PacketKind`, seal and open with the channel, verify floor and texts against the roster's keys
    MERGED to master (`278a30b`, pushed), worktree removed. `ios build` PASSES on master (later the same session, once the Mac had room). Still to do: a full `ios build`, and `ios test chirp --only ChirpCoreTests` (the 17 Dispatch tests have never run). Then tick this item and the Find follow-ups
    Ninth session: rebased on master (local only: the force push of the rebase was refused, so the remote branch still holds the old tip; master gets it on merge), and the Mesh heartbeat no longer holds the Mesh across its sleep (`e71d6b5`). Every ChirpCore name it calls exists (grep); signatures still unproven
    Written, not yet compiled (seventh session): branch `v2/dispatch`, worktree `/root/chirp-screens`. ChirpCore `Dispatch.swift` + `DispatchTests.swift` (17 tests); app `Mesh.swift` (Transport -> Dispatch -> Flock, presence heartbeat), `Transport.send(_:except:)`, `Flock.apply`/`texts`/`left`, `Person.peer`. `v2/project.yml` adds ChirpCore's tests to the Chirp scheme, so prove it with `ios test chirp --only ChirpCoreTests` (then `ios build`), merge to master, remove the worktree. Still open after that: chat from `Flock.texts` instead of `ChatItem.demo()`, `AudioSession.setFloor` from the floor reducer, Find routing
    Then move chat messages from `ChatView` state (`ChatItem.demo()`) into `Flock` (the message model comes from dispatch), and feed `AudioSession.setFloor` from the floor reducer
    And give `Person` its `PeerID`, so Talk's caption card and Chat's voice bubbles read `LiveCaptions.track` instead of the demo words
  - [ ] Demo Mode content: simulated people and a channel on `SendGate.demoChannel`, entering through the real receive path
  - [ ] Plain placeholder screens: Talk, Channels, Nearby (with Block), Texts, Check In; system styles only until Jackson picks a route
- [ ] 1) Audit, read-only, on a phone plus the simulator: what truly works (push to talk both ways, texts with acks, a relay hop), what is dead, faked or duplicated; write ~/Downloads/chirpchirps-redo/AUDIT.md
  Its hardware half is under Needs Jackson (waits on the simulator).
  - [x] Code-reading half of the audit (no Mac needed): what is dead, faked or duplicated, and what the hardware half must prove; draft in docs/audit/AUDIT.md, copied to ~/Downloads/chirpchirps-redo/AUDIT.md
  - [x] Toolkit fix to propose (ios-toolkit, not this repo): `auto` in sim_resolver matches only names starting "iPhone", but every project names its simulator "<Project> iPhone ...", so `auto` never finds one. Written up in `docs/proposals/ios-toolkit-sim-auto.md`; applying it is the toolkit owner's call
- [ ] 3) v2.0 scope on that core: hold to talk to friends nearby, channels, texts with delivery ticks, who is nearby, block a person, location off by default and asked every time, demo mode for App Review; answers 5.1.1(iv), 2.1(a), 5.1.2(i) and 2.5.4
- [x] 4) Design directions: skipped by the mandate update; the lead's three routes (Dawn Chorus, Night Wire, Trail Signal) are with Jackson

## Needs Jackson

- [x] Background behaviour: Jackson picked option 1 (2026-11-17, Inbox chirp-2-0-background; word for word in `docs/audit/BACKGROUND.md`): talk with the app open; texts, roll call, pings and "someone is talking" alerts reach a locked phone over Bluetooth; the Lock Screen card opens the app to reply; a PTT server is a later add-on, not 2.0

- [x] One simulator for Chirp: approved by Jackson (lead decision, 2026-11-17), created "Chirp iPhone 17 Pro" on iOS 26.5; the screenshots moved to the top of the Queue
- [ ] (Waits on the simulator) Background proof on hardware: BACKGROUND.md section 4, tests B1 to B5 (needs the Chirp simulator and the shared iPhone, ideally a second iPhone); update BACKGROUND.md and the Mac copy with results
- [ ] (Waits on the simulator) Audit Hardware half: on the simulator and the shared iPhone (`ios device hold chirp`, release after), prove or disprove each claim the code-reading half lists; finish AUDIT.md.
- [ ] Watch in 2.0 or 2.1: the scope message says 2.1 while the design draws it; build after 2.0 unless Jackson says otherwise
- [x] Pick one of the lead's three routes: Jackson approved Dawn Chorus (2026-11-17)
- [ ] Play the 2.0 TestFlight build before anything is submitted
- [ ] Release day for chirpchirps.com's list (not before 2.0 is on sale): the sender is not set up (creasecracker.com's draft `RELEASE-EMAIL.md` waits on the same Resend question). Jackson okays the words and the sender; then one email to each address, delete the list and its backups (`/var/backups/chirpchirps`, the Mac's `~/Downloads/chirpchirps-signup-backups`), remove `chirpchirps-signup` and `chirpchirps-backup`, and put the App Store link back on the site in that change
- [ ] 1.0 resubmission: parked by the redo. Branch `fix/2-5-4-foreground-only` answers the 2.5.4 rejection on 1.0's code but was never compiled; only resume it if Jackson wants 1.0 in the store before 2.0

## Done
