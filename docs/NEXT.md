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

Note from the session that wrote this (not Jackson's words): there were FOUR rejections, not
three. The fourth, and the one 1.0 is rejected under today, is **Guideline 2.5.4**: the build
declared the `audio` background mode. 2.0 must declare no `UIBackgroundModes` and be
foreground-only, or it will be rejected the same way. Details and a worked fix (on 1.0's code)
are on branch `fix/2-5-4-foreground-only`, in `docs/sessions/2026-11-17-review-2-5-4.md`.
Handoff: `docs/sessions/2026-11-17-handoff.md`.

## Queue

- [ ] 1) Audit, read-only, on a phone plus the simulator: what truly works (push to talk both ways, texts with acks, a relay hop), what is dead, faked or duplicated; write ~/Downloads/chirpchirps-redo/AUDIT.md
  - [ ] Code-reading half of the audit (no Mac needed): what is dead, faked or duplicated, and what the hardware half must prove; draft in docs/audit/AUDIT.md, copied to ~/Downloads/chirpchirps-redo/AUDIT.md
  - [ ] Hardware half: on the simulator and the shared iPhone (`ios device hold chirp`, release after), prove or disprove each claim the code-reading half lists; finish AUDIT.md
  - [ ] Toolkit fix to propose (ios-toolkit, not this repo): `auto` in sim_resolver matches only names starting "iPhone", but every project names its simulator "<Project> iPhone ...", so `auto` never finds one
- [ ] 2) New clean project: carry over only code the audit proves on hardware (likely the audio and transport core), rewritten clean with tests; everything else is new; no UIBackgroundModes (2.5.4)
- [ ] 3) v2.0 scope: hold to talk to friends nearby, channels, texts with delivery ticks, who is nearby, block a person, location off by default and asked every time, demo mode for App Review; answers 5.1.1(iv), 2.1(a), 5.1.2(i) and 2.5.4
- [ ] 4) Design: 3 truly different directions as Talk-screen phone mockups in ~/Downloads/chirpchirps-redo/design/ (not the old amber radio look, not another studio app's style), then file ONE Inbox item for Jackson to pick, and stop; no UI build before he picks

## Needs Jackson

- [ ] Create, or let me create, one simulator for Chirp ("Chirp iPhone 17 Pro", installed iOS 26.5 runtime): Inbox item ref chirp-2-0-jackson, filed 2026-11-17. The foreman allows only ios build/run/test, which cannot create one; blocks the hardware half of the audit
- [ ] Pick one of the 3 design directions (after item 4; Inbox item)
- [ ] Play the 2.0 TestFlight build before anything is submitted
- [ ] 1.0 resubmission: parked by the redo. Branch `fix/2-5-4-foreground-only` answers the 2.5.4 rejection on 1.0's code but was never compiled; only resume it if Jackson wants 1.0 in the store before 2.0

## Done
