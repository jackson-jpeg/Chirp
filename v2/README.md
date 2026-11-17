# ChirpChirps 2.0: the clean project

Jackson's mandate (2026-11-17, in `docs/NEXT.md`): a full redo. Carry over only what the audit
proves, rewritten clean with tests. Everything else is new. Until Jackson picks one of the three
design routes, the screens are plain placeholders.

1.0 stays where it is (`Chirp/`, `ChirpTests/`, `project.yml`) until 2.0 replaces it. Nothing in
`v2/` imports from it.

## Layout

- `ChirpCore/`: a Swift package with only Foundation and CryptoKit. Every rule that decides
  something lives here, so it is tested with `swift test` on the Mac with no simulator and no
  radio. Run it:
  `rsync -a --delete --exclude .build v2/ChirpCore/ macbook:Chirp-v2-core/v2/ChirpCore/` then
  `heavy -- ssh macbook-tunnel "cd ~/Chirp-v2-core/v2/ChirpCore && swift test"`.
- Still to come: the app target (`project.yml` with no `UIBackgroundModes`), the
  MultipeerConnectivity transport, the audio engine (Opus, capture and playback) and its
  session lifecycle, dispatch, texts, Demo Mode content and the placeholder screens.

## What is in ChirpCore, and which audit finding each file answers

| File | What it is | Audit (docs/audit/AUDIT.md) |
|---|---|---|
| `Identity.swift` | `PeerID` = 16 bytes of SHA-256 of the Ed25519 key; the only key for a person. Keys in a `KeyStore` (Keychain in the app). | Section 5: three identities for one person |
| `Packet.swift` | Wire format v2: version, explicit kind, TTL, real hop count, origin, per-launch epoch, sequence, channel on every packet. | Defect 1 (no channel on voice), fake hops (section 4), magic-string dispatch (section 7) |
| `Router.swift` | Dedup, replay window per (origin, epoch, kind), block filter, relay with hop count. A value with no callbacks. | Defect 2 at the router (H5); section 4 relay counts |
| `Floor.swift` | Pure floor reducer scoped to one channel, with a silence timeout and a talk cap; no `floorGranted`. | Defect 1 (H6), H15, dead `floorGranted` |
| `JitterBuffer.swift` | One speaker stream (peer, epoch) at a time; a new stream resets it. | Defect 2 (H5) |
| `Channel.swift` | Invite code and HKDF key carried over; a locked channel seals every payload, voice included, bound to the header. | H7; epoch rotation dropped (section 4) |
| `Roster.swift` | Signed presence (no battery level) and the one nearby list, block-filtered. | Section 5: four nearby sources; H18 |
| `Blocking.swift` | Block list keyed by `PeerID`. | 5.1.2(i); H18, H19 |
| `LocationConsent.swift` | Check-in reducer: off at launch, our sheet every time, the iOS prompt only after a yes, 15 minutes, ends in background. | 5.1.2(i), 5.1.1(iv) |
| `Texts.swift` | Signed texts, acks only on a joined channel, ticks stored with the message. | H8, H9; two acks with one magic (section 5) |
| `AudioSessionPolicy.swift` | When the session is open: record only while holding, playback only while someone talks plus a 2 s tail, nothing in background, at launch or in an interruption. | 2.5.4 (section 6), H1, H13 |
| `SendGate.swift` | Demo channels are recognisable from the header; nothing leaves or enters while sandboxed. | 2.1(a) |

## Rules 2.0 holds to (from the four rejections)

- **2.5.4**: no `UIBackgroundModes`. The audio session opens on a press or an incoming floor and
  closes when idle and on backgrounding. See branch `fix/2-5-4-foreground-only`.
- **5.1.1(iv)**: no system prompt before the user acts. Local Network starts on the first tap
  that needs it, microphone on the first press, location only after our own consent sheet.
- **5.1.2(i)**: block a person from the nearby list and from any message; location consent can
  be declined and is asked every check-in.
- **2.1(a)**: Demo Mode lets a reviewer use every screen alone, with nothing reaching the radio.
