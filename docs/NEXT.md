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

- [ ] Dawn Chorus build (branch `v2/dawn-chorus`)
  - [x] App icon rendered at 1024 from Main's SVG (`v2/design/icon/AppIcon.svg`, `v2/scripts/render-svg.mjs`)
  - [x] The bird as one SwiftUI view from the design's paths (`v2/scripts/gen-bird-paths.py` writes `BirdPaths.swift`; `BirdView`, `BirdRenderer`, seven `BirdPalette`s; ChirpCore's set is now 7 colors and 3 chirps to match)
  - [x] Theme tokens light and dark, Nunito bundled (OFL), shared components, `v2/project.yml` (no UIBackgroundModes)
  - [x] Screens, light then dark: Welcome, MakeBird, Talk (listen and hold), Chat, Nearby (with Block), Find, Meetup, RollCall, CatchUp; compile clean (no warnings; 88 core tests pass). Not yet seen running: the match to the PNGs is unproven until the screenshots
  - [ ] Fold the screen-local color tokens (`ChatStyle`, `CoverTokens`, Welcome's sky) into `Theme.swift`, and let `WireScene` draw Talk's and Welcome's scenes (both redraw it today)
  - [ ] Chat messages and the chosen chirp live in view state and `@AppStorage`; move them into `Flock` when dispatch lands
  - [ ] Simulator screenshots of each screen, light and dark, next to the design PNG in ~/Downloads/chirpchirps-redo/build-vs-design/; then one Inbox item (needs the simulator)
  - [ ] LockScreen (Live Activity): waits on Jackson's background answer (Inbox `chirp-2-0-background`)
  - [ ] Watch: the scope message says Apple Watch is 2.1 while the design draws it; build after 2.0 unless Jackson says otherwise

## Scope addition (the lead, relayed through Jackson's Sessions page, 2026-11-17; word for word)

> 2.0 scope grew (add to docs/NEXT.md, core first, styled UI still waits for Jackson's pick): build the core so it supports these. 1) Whisper: talk to one person, not the group. 2) Live captions on every voice message, on-device speech to text, captions-only mode. 3) Catch up: friends' phones hold messages for someone out of range and deliver them in order when they return (store and forward, with a cap). 4) Find: Nearby Interaction precision finding between iPhones with the UWB chip, plain distance fallback, plus Ping that makes a friend's phone chirp loudly. 5) New message types: meet-up spot (place, time, who's coming), roll call (are you OK, I need help with priority relay), small photos, battery level. 6) Each person's bird (colors) and their own start-talking chirp sound. 7) Lock screen and Dynamic Island Live Activity with a talk button. Before anything else, prove the app keeps receiving with the phone locked and no signal, and write what you find in ~/Downloads/chirpchirps-redo/BACKGROUND.md. That decides whether 7 is possible. Apple Watch and translation are 2.1.

What the background research found (`docs/audit/BACKGROUND.md`, also in
~/Downloads/chirpchirps-redo/): live voice while locked with no signal is not possible within
App Store rules as far as Apple's documentation goes. Texts and alerts over Bluetooth LE might
work. MultipeerConnectivity is deprecated in Xcode 27, so 2.0's transport moves to Network
framework. Hardware proof is still to come.

- [ ] Background proof on hardware: BACKGROUND.md section 4, tests B1 to B5 (needs the Chirp simulator and the shared iPhone, ideally a second iPhone); update BACKGROUND.md and the Mac copy with results
- [ ] Core for the new scope, in ChirpCore with tests, in this order (done so far: `Whisper.swift`, `Messages.swift`, `CatchUp.swift`, `Bird.swift`, `Photo.swift`, `Find.swift`, 88 tests; Whisper is a private two-person channel, so relays cannot tell who it is for):
  - [x] Whisper: a packet addressed to one PeerID, sealed pairwise (`LocalIdentity.sharedKey`), relayed but delivered only to that person, with its own floor
  - [x] Roll call and meet-up spot message kinds; roll call "I need help" gets priority relay (a higher TTL and first in the send queue)
  - [x] Catch up: store and forward of texts for an absent friend, with a cap per person and in total, delivered in order, deduped by message ID
  - [x] Battery level: sent only to friends, never in the public presence (the audit flagged 1.0 broadcasting it to strangers)
  - [x] Ping: a message kind that asks a friend's phone to chirp; rate-limited, only from friends, never from blocked people
  - [x] Each person's bird: colors and a chirp choice carried in the signed presence (an ID from a fixed set, not raw audio)
  - [x] Small photos: a capped, chunked message kind (size limit, sealed on locked channels)
  - [ ] Captions (app side, needs `ios build`, so the simulator): on-device speech to text of received voice in the app (Speech framework); the speech permission asked on the first tap of captions, never at launch (5.1.1(iv)); captions-only mode
  - [x] Find, core part: Nearby Interaction token exchange over the whisper channel (friends only) and an honest in range / through others / out of range fallback (`Find.swift`)
  - [ ] Find, app part: NISession ranging from the exchanged tokens, the NI permission asked on the first Find tap; needs `ios build` (simulator) and two UWB iPhones to prove
- [ ] Transport on Network framework (Bonjour with peer-to-peer Wi-Fi) instead of MultipeerConnectivity (deprecated in Xcode 27 beta); replaces the MultipeerConnectivity transport sub-item under item 2
- [ ] 7) Lock Screen / Dynamic Island: decided by Jackson's answer on BACKGROUND.md's options (Needs Jackson)

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
  - [ ] Audio session opened only while talking or listening, closed on background; no UIBackgroundModes (2.5.4; see branch fix/2-5-4-foreground-only). The rule is done and tested in ChirpCore (`AudioSessionPolicy`); left: the app's AVAudioSession adapter that follows it, with interruption and route-change handling (1.0's `AudioSessionManager.swift:84-164` is the checklist)
  - [ ] Audio engine in the app: capture to 16 kHz Opus 20 ms frames and playback through ChirpCore's JitterBuffer; carry over the render-thread copy, the persistent converter and the DEBUG sine mic (audit section 7)
  - [ ] Transport in the app: MultipeerConnectivity behind one send gate (ChirpCore `SendGate`), peers keyed by PeerID from presence, an invitation tie-break, advertising and browsing only after the first tap that needs them (5.1.1(iv))
  - [ ] Dispatch in the app: one switch on `PacketKind`, seal and open with the channel, verify floor and texts against the roster's keys
  - [ ] Demo Mode content: simulated people and a channel on `SendGate.demoChannel`, entering through the real receive path
  - [ ] Plain placeholder screens: Talk, Channels, Nearby (with Block), Texts, Check In; system styles only until Jackson picks a route
- [ ] 1) Audit, read-only, on a phone plus the simulator: what truly works (push to talk both ways, texts with acks, a relay hop), what is dead, faked or duplicated; write ~/Downloads/chirpchirps-redo/AUDIT.md
  - [x] Code-reading half of the audit (no Mac needed): what is dead, faked or duplicated, and what the hardware half must prove; draft in docs/audit/AUDIT.md, copied to ~/Downloads/chirpchirps-redo/AUDIT.md
  - [ ] Hardware half: on the simulator and the shared iPhone (`ios device hold chirp`, release after), prove or disprove each claim the code-reading half lists; finish AUDIT.md. Waits on the simulator (Needs Jackson)
  - [x] Toolkit fix to propose (ios-toolkit, not this repo): `auto` in sim_resolver matches only names starting "iPhone", but every project names its simulator "<Project> iPhone ...", so `auto` never finds one. Written up in `docs/proposals/ios-toolkit-sim-auto.md`; applying it is the toolkit owner's call
- [ ] 3) v2.0 scope on that core: hold to talk to friends nearby, channels, texts with delivery ticks, who is nearby, block a person, location off by default and asked every time, demo mode for App Review; answers 5.1.1(iv), 2.1(a), 5.1.2(i) and 2.5.4
- [x] 4) Design directions: skipped by the mandate update; the lead's three routes (Dawn Chorus, Night Wire, Trail Signal) are with Jackson

## Needs Jackson

- [ ] Background behaviour: pick an option in `docs/audit/BACKGROUND.md` section 3 (recommended: foreground voice, texts and alerts over Bluetooth LE while locked; no `audio` background mode). Decides scope item 7. Inbox item ref chirp-2-0-background

- [ ] Create, or let me create, one simulator for Chirp ("Chirp iPhone 17 Pro", installed iOS 26.5 runtime): Inbox item ref chirp-2-0-jackson, filed 2026-11-17. The foreman allows only ios build/run/test, which cannot create one; blocks the hardware half of the audit, and every `ios build` of the 2.0 app target (`ios` resolves a simulator even to compile). ChirpCore does not need it: its tests run with `swift test` on the Mac
- [ ] Pick one of the lead's three routes (Dawn Chorus, Night Wire, Trail Signal); every styled screen waits for it
- [ ] Play the 2.0 TestFlight build before anything is submitted
- [ ] 1.0 resubmission: parked by the redo. Branch `fix/2-5-4-foreground-only` answers the 2.5.4 rejection on 1.0's code but was never compiled; only resume it if Jackson wants 1.0 in the store before 2.0

## Done
