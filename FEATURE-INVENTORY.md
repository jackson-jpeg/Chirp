# ChirpChirp — Feature Inventory

**Purpose:** give you what you need to decide the v1 cut list. Document only.
**Nothing has been deleted and nothing will be until you say so.**

Counted on the VPS against commit `1044dc0`. Total app source: **44,115 lines**
across 166 Swift files in `Chirp/Sources`.

---

## How to read the columns

**(a) Reachable from UI** — can a user actually get to it in the shipped app.
Checked by tracing navigation from `HomeView` and `MoreView`.

**(b) Does it work** — deliberately harsh, because I want this column to be
worth something:

| Grade | Meaning |
|---|---|
| **Works** | Tests exercise it, or I traced it end to end. |
| **Unverified** | Plausible from the code. Never run on a device by me. This is most of the app. |
| **Can't work** | A concrete structural reason it cannot function as written. Named in every case. |

**(c) Leak risk** — unbounded in-memory growth. **Read, not measured.** I have
not run Instruments against any of this. Treat as "worth checking", not "proven".

**(d) LOC** — service plus its own views. Shared infrastructure is counted once
against the core, not against each feature that uses it.

**(e) PTT survives without it** — does the walkie-talkie still work if this is
deleted. This is the column that decides the cut list.

**(f) App Store risk** — my assessment. I am not a reviewer and Apple's
decisions are not perfectly predictable, so treat High as "get advice", not
"certain rejection".

---

## The core — not candidates for cutting

This is the walkie-talkie. Everything else exists around it.

| Feature | LOC | Notes |
|---|---:|---|
| Push-to-talk engine, audio capture/playback, Opus codec, jitter buffer, floor control | ~940 | Contains defects #1 and #2. This is where the stabilization work goes. |
| MultipeerConnectivity transport, mesh router, peer tracker | ~1,710 | Contains defects #3 and #4. |
| Channels, text messaging, persistence | ~1,030 | Text messaging is well tested and healthy. |
| Home / Channel / Chat / Settings / Onboarding views | ~5,090 | Some of this is presentation for features below and shrinks if they're cut. |
| Models, packets, utilities, app shell | ~3,700 | |
| **Core total** | **~12,500** | ~28% of the app |

**The other ~31,600 lines — 72% — are the features below.**

---

## Full inventory

Ordered by cost to keep, most expensive first.

### 1. Protect suite (BLE tracker scanning, room scanner, sound alerts, privacy shield)

| | |
|---|---|
| (a) Reachable | Yes — More → Protect |
| (b) Works | **Partly can't work.** `SoundAlertService` carries two `nonisolated(unsafe)` properties the compiler explicitly reports as having *no effect*, so its thread-safety story is not what the code claims. BLE scanning is unverifiable in the simulator and unverified on device. |
| (c) Leak risk | **High.** 5 collections in `BLEScanner`, 4 in `PrivacyShield`, 4 in `SoundAlertService`, with weak trimming. `PrivacyShield` runs a repeating timer. |
| (d) LOC | **2,144** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **Medium–High.** An app that scans for and identifies nearby Bluetooth trackers is adjacent to Apple's own anti-stalking feature and to a category reviewers look at closely. Also drives the `NSBluetoothAlwaysUsageDescription` string. |

**Cost to keep: highest in the app.** Largest single non-core surface, worst leak signals, an unverifiable core mechanism, and real review risk. It is also completely unrelated to a walkie-talkie.

---

### 2. Maps (mesh map, geo map, offline map downloads)

| | |
|---|---|
| (a) Reachable | Yes — Home → map, More → Mesh Map |
| (b) Works | Unverified. Map rendering itself is MapLibre's, which is mature. |
| (c) Leak risk | Medium — `OfflineMapManager` holds an untrimmed collection; tile caches are the usual suspect. |
| (d) LOC | **2,423** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **Low**, with one exception: this is the main consumer of location, and the location permission situation is a problem in its own right (see the cross-cutting section). |

**Cost to keep: high, mostly in lines and in the third-party dependency (MapLibre, 6.25.0), not in risk.** This is the most *plausible* feature to keep of the large ones — users expect a mesh app to show peers on a map. But it's 2,423 lines, and it is not the walkie-talkie.

---

### 3. Positioning: UWB, dead reckoning, Lighthouse indoor positioning

| | |
|---|---|
| (a) Reachable | Partly — surfaces through the map and peer distance readouts |
| (b) Works | **Lighthouse can't work.** It calls `NEHotspotNetwork.fetchCurrent` for Wi-Fi fingerprinting; that API requires the Access WiFi Information entitlement, which is **not** in `Chirp.entitlements`. It will return nil forever and the feature will silently produce nothing. UWB and dead reckoning are unverified and UWB needs U1/U2 hardware on both ends. |
| (c) Leak risk | Medium — plus a GRDB database (`LighthouseDatabase`, 423 lines) accumulating breadcrumb trails with no retention policy I could find. |
| (d) LOC | **1,809** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **Medium.** Drives `NSNearbyInteractionUsageDescription` and `NSMotionUsageDescription`. A crowd-sourced radio-fingerprint database shared over a mesh is a privacy-questionnaire conversation you do not want during v1 review. |

**Cost to keep: high, and one third of it is provably inert.** Strongest cut candidate on evidence rather than opinion.

---

### 4. Emergency SOS

| | |
|---|---|
| (a) Reachable | Yes |
| (b) Works | **Can't work as described.** The Info.plist declares `NSLocationAlwaysAndWhenInUseUsageDescription` with the purpose string *"background location for emergency SOS broadcasting"*, but the app declares **no `location` background mode**. Background SOS broadcasting is not possible. |
| (c) Leak risk | Low |
| (d) LOC | **1,510** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **High — and this one I'd raise even if you keep everything else.** Two separate problems. First, declaring an Always-location purpose the app cannot fulfil is a rejection risk on its own. Second, and more seriously: **an emergency/SOS feature that a user might rely on in a real emergency, in an app that currently has unresolved crash defects in its audio and transport layers, is a liability question, not just a review question.** |

**Cost to keep: high, and the risk is not primarily technical.** My recommendation is to cut it for v1 regardless of what you decide about the rest — and if it ever ships, it ships with the background-location capability properly declared and after the crash work is finished.

---

### 5. MeshCloud (distributed encrypted backup, Shamir secret sharing)

| | |
|---|---|
| (a) Reachable | Yes — More → Mesh Cloud |
| (b) Works | Unverified end to end. The cryptographic primitives are tested (`ShamirSplitterTests`, `MeshCloudTests`) and those tests pass. Whether distribute-and-retrieve works across real devices is unknown. |
| (c) Leak risk | Medium — chunk stores with no eviction I could find. |
| (d) LOC | **1,232** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **Medium.** Feeds the encryption-declaration problem in the cross-cutting section. |

**Cost to keep: high.** Genuinely clever, genuinely unrelated to talking to someone.

---

### 6. Witness (cryptographic attestation of captured media)

| | | 
|---|---|
| (a) Reachable | Yes — More → Witness |
| (b) Works | Unverified. `WitnessTests` cover the attestation format and pass. |
| (c) Leak risk | Low |
| (d) LOC | **1,224** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **Medium.** Camera permission, and a feature whose entire premise is evidentiary integrity invites scrutiny of claims made in the description. |

**Cost to keep: high.**

---

### 7. Gateway (relay messages out of the mesh)

| | |
|---|---|
| (a) Reachable | Yes — Home sheet and More |
| (b) Works | Unverified |
| (c) Leak risk | Low–Medium |
| (d) LOC | **1,221** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **Medium.** Depends entirely on what it gateways *to* — I have not traced the egress path, and that determination changes the answer. Flagging as an open question rather than guessing. |

---

### 8. Dead drops (location-gated hidden messages)

| | |
|---|---|
| (a) Reachable | Yes — More → Dead Drops |
| (b) Works | Now plausible. **This is where the crash I fixed in `c361032` lived** — the geohash neighbour lookup underpinning area matching was returning wrong cells and hard-crashing on ~12.5% of locations. Untested on device either way. |
| (c) Leak risk | Low |
| (d) LOC | **1,092** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **Medium.** Location-gated anonymous message caches are a moderation-surface question. |

---

### 9. CHORUS (pipeline-parallel CoreML inference across peers)

| | |
|---|---|
| (a) Reachable | Yes — More → Chorus |
| (b) Works | **Unverified, and I rate the odds low.** Partitioning a CoreML model's layers across phones and streaming activations between them over MultipeerConnectivity is a research-grade problem. `ChorusTests` cover the negotiation message format, not the inference. |
| (c) Leak risk | **High** — 6 collections, weak trimming, holds intermediate tensors. |
| (d) LOC | **1,090** |
| (e) PTT survives | **Yes** |
| (f) Store risk | Low–Medium |

**Cost to keep: high, and the payoff is speculative.**

---

### 10. SWARM (distributed CoreML compute across peers)

| | |
|---|---|
| (a) Reachable | Yes — More → Swarm |
| (b) Works | Unverified |
| (c) Leak risk | **High** — 6 collections including a work queue and a completed-results map. |
| (d) LOC | **1,058** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **High.** It registers a `BGProcessingTask` (`com.chirpchirp.swarm.compute`) to **donate the user's device to background computation for other users' workloads**. Background compute-sharing is exactly the kind of resource use reviewers ask pointed questions about, and it has a battery/thermal story you'd need to defend. |

**Cost to keep: high, with the highest review risk per line in the app.**

---

### 11. CICADA (steganography — hide messages in text, images, audio)

| | |
|---|---|
| (a) Reachable | Yes — chat input overlay |
| (b) Works | Probably. `TextStegoTests`, `ImageStegoTests`, `AudioStegoTests` all pass. |
| (c) Leak risk | Low |
| (d) LOC | **1,051** |
| (e) PTT survives | **Yes** |
| (f) Store risk | **High.** Covert-channel messaging designed to be undetectable inside innocuous content is a feature reviewers can read as evasion. Combined with the encryption declaration problem below, this is the pairing I would least like to defend in a v1 review. |

**Cost to keep: high on risk, moderate on lines.**

---

### 12. Babel (real-time translation)

| | |
|---|---|
| (a) Reachable | Yes — More → Babel |
| (b) Works | **Suspect.** The build emits, at `BabelService.swift:376`: `no calls to throwing functions occur within 'try' expression` and `no 'async' operations occur within 'await' expression` on the `TranslationSession` construction. The compiler is saying the call it's awaiting does nothing asynchronous — that is not what a working translation session looks like. Worth a closer read before trusting it. |
| (c) Leak risk | Low–Medium |
| (d) LOC | **982** |
| (e) PTT survives | **Yes** |
| (f) Store risk | Low–Medium — drives `NSSpeechRecognitionUsageDescription`. |

---

### 13. Darkroom (ephemeral encrypted image viewing)

| | |
|---|---|
| (a) Reachable | Yes — More → Darkroom |
| (b) Works | Unverified. `DarkroomCryptoTests` pass. |
| (c) Leak risk | Medium — `DarkroomRenderer` holds 2 `nonisolated(unsafe)` Metal properties. |
| (d) LOC | **934** |
| (e) PTT survives | **Yes** |
| (f) Store risk | Low–Medium |

---

### 14. Voice messages (async recorded messages)

| | |
|---|---|
| (a) Reachable | Yes — More → Voice Messages |
| (b) Works | Unverified |
| (c) Leak risk | Medium |
| (d) LOC | **811** |
| (e) PTT survives | **Yes** — though this is the closest thing on the list to a natural walkie-talkie companion feature. |
| (f) Store risk | Low |

---

### 15. Mesh intelligence + pheromone routing

| | |
|---|---|
| (a) Reachable | Indirectly — affects routing, surfaced in diagnostics |
| (b) Works | Unverified. `MeshIntelligenceTests` and `PheromoneRoutingTests` pass. |
| (c) Leak risk | **Medium–High** — 7 collections in `MeshIntelligence` holding per-peer topology history. |
| (d) LOC | **652** |
| (e) PTT survives | **Yes** — it's an optimisation layer over routing that already works without it. |
| (f) Store risk | Low |

**Note:** cutting this is lower-risk than it sounds, but it is more entangled with the core than the standalone features are, so it's a more careful removal.

---

### 16. Wi-Fi Aware transport

| | |
|---|---|
| (a) Reachable | Indirectly — second transport |
| (b) Works | Unverified. Requires iOS 26 and the `com.apple.developer.wifi-aware` entitlement, which **is** present. |
| (c) Leak risk | Low–Medium |
| (d) LOC | **537** |
| (e) PTT survives | **Yes** — MultipeerConnectivity is the primary transport. |
| (f) Store risk | **Medium.** Wi-Fi Aware is a managed capability. Shipping it means defending it; cutting it means the entitlement should come out of `Chirp.entitlements` too. |

**You have already decided to cut this for v1.** Listed for completeness and to
flag the entitlement, which is easy to leave behind.

---

### 17. File transfer

| | |
|---|---|
| (a) Reachable | **Partly not.** `FileTransferBubbleView` and `DocumentPickerView` exist; `FileTransferBubbleView` has **zero references** anywhere in the codebase. |
| (b) Works | Unverified. `FileTransferTests` pass. |
| (c) Leak risk | Medium |
| (d) LOC | **498** |
| (e) PTT survives | **Yes** |
| (f) Store risk | Low |

---

### 18. Live transcription

| | |
|---|---|
| (a) Reachable | Yes — overlay during PTT |
| (b) Works | Unverified |
| (c) Leak risk | Low |
| (d) LOC | **499** |
| (e) PTT survives | **Yes** |
| (f) Store risk | Low–Medium — speech recognition permission. |

---

### 19. Live Activities

| | |
|---|---|
| (a) Reachable | **No — already disabled.** The call that would start one is commented out in `AppState.start()` (`AppState.swift:864–865`). |
| (b) Works | Not running |
| (c) Leak risk | None |
| (d) LOC | **406** plus a separate app-extension target |
| (e) PTT survives | **Yes** |
| (f) Store risk | Low, but `NSSupportsLiveActivities: true` and the extension target are still declared for a feature that does nothing. |

**You have already decided to cut this.** It is the cheapest cut on the list —
mostly deleting a target and two Info.plist lines.

---

### 20. Background mesh service + silent-tone keep-alive

| | |
|---|---|
| (a) Reachable | No UI |
| (b) Works | **No.** MultipeerConnectivity does not survive backgrounding on the `audio` background mode alone, so the service cannot do what its own doc comment claims. |
| (c) Leak risk | Low |
| (d) LOC | ~250 |
| (e) PTT survives | **Yes — it survives *better*.** |
| (f) Store risk | **Highest single item in the app.** Playing an inaudible 20 Hz tone at −60 dB purely to avoid suspension is a well-known rejection pattern; it is using a background mode for something other than its declared purpose. |

**This is defect #1's antagonist and it is already scheduled for deletion in the
re-scoped D-1.** It is the one item on this list where cutting is unambiguously
a bug fix rather than a scope decision.

---

### 21. MeshShield (triple-layer encryption)

| | |
|---|---|
| (a) Reachable | No UI — always on for mesh messages |
| (b) Works | Unverified. `SecurityHardeningTests` pass. Carries 5 TODO/FIXME markers, the most of any service. |
| (c) Leak risk | Low |
| (d) LOC | **269** |
| (e) PTT survives | Yes, but it is the message confidentiality story |
| (f) Store risk | See encryption declaration below |

**Not a cut candidate** — small, and removing encryption is a product decision in
the wrong direction. Listed because of the TODOs and the declaration issue.

---

### Dead code — zero references anywhere

Not features, just unreferenced files. Safe to delete independently of any
product decision:

| File | LOC (approx) |
|---|---:|
| `Views/Components/FileTransferBubbleView.swift` | 143 |
| `Views/Protect/FilesTabView.swift` | ~120 |
| `Views/Components/ProtectStatusBar.swift` | ~80 |
| `Views/Components/StatusPillView.swift` | ~60 |
| `Views/Components/WaveformView.swift` | ~90 |

I have **not** deleted these. Verified by grepping each view's type name across
all Swift sources and excluding its own declaration.

---

## Cross-cutting issues that survive any cut list

These are not features and cutting features will not fix them.

**1. Privacy manifest declares no collected data.** `PrivacyInfo.xcprivacy` has an
empty `NSPrivacyCollectedDataTypes` while the app records audio, reads precise
location, reads the photo library, and transmits all of it to other devices. Even
if peer-to-peer transmission doesn't meet Apple's definition of "collection" by
the developer, the App Store Connect privacy questionnaire will need entries, and
a manifest that contradicts the questionnaire is something reviewers notice. **You
flagged this as a P0 blocker and I agree.** It needs a decision per data type, not
a guess from me.

**2. Encryption declaration.** `ITSAppUsesNonExemptEncryption: false` is declared,
while the app performs Curve25519 key agreement, Ed25519 signing, AES-GCM-256
across MeshShield, MeshCloud, Darkroom, CICADA and channel crypto. Whether that
qualifies for the standard exemption is a compliance question with a real answer,
and "false" was almost certainly filled in without asking it. **Worth 30 minutes
with the actual criteria before submission.**

**3. Location permission mismatch.** `NSLocationAlwaysAndWhenInUseUsageDescription`
promises background SOS broadcasting; there is no `location` background mode.
Either the capability is added or the string comes out. Currently the app asks
for a permission it structurally cannot use.

**4. Background modes.** `UIBackgroundModes: [audio]` exists to serve item 20,
which is being deleted. Once it's gone, this claim needs re-justifying or removing.

---

## Ranked cost to keep — the short version

| Rank | Feature | LOC | Why it costs |
|---:|---|---:|---|
| 1 | Protect suite | 2,144 | Biggest, worst leak signals, unverifiable, real risk |
| 2 | Emergency SOS | 1,510 | Can't work as described + liability |
| 3 | Positioning / UWB / Lighthouse | 1,809 | A third of it provably inert |
| 4 | SWARM | 1,058 | Highest review risk per line |
| 5 | CICADA steganography | 1,051 | Covert-channel review risk |
| 6 | CHORUS | 1,090 | Speculative payoff, high leak risk |
| 7 | Maps | 2,423 | Big, but the most defensible large feature |
| 8 | MeshCloud | 1,232 | Clever, unrelated |
| 9 | Witness | 1,224 | Unrelated |
| 10 | Gateway | 1,221 | Risk depends on unanswered egress question |
| 11 | Dead drops | 1,092 | Moderation surface |
| 12 | Babel | 982 | Compiler suggests it may not work |
| 13 | Darkroom | 934 | |
| 14 | Voice messages | 811 | Closest natural fit to a walkie-talkie |
| 15 | Mesh intelligence / pheromone | 652 | More entangled with core |
| 16 | Wi-Fi Aware | 537 | Already cut by you |
| 17 | Live transcription | 499 | |
| 18 | File transfer | 498 | Partly unreachable |
| 19 | Live Activities | 406 | Already cut by you; cheapest removal |
| 20 | Background mesh service | ~250 | Already scheduled for deletion; is a bug |

---

## What I did not verify

Stated plainly, because this document would be misleading without it.

- **I ran nothing on a physical device.** Not one feature in this inventory has
  been observed working. Every "Unverified" is literal.
- **The leak column is read, not measured.** No Instruments run, no allocation
  trace. It is a count of collections against a count of trimming operations —
  a heuristic that will have both false positives and false negatives.
- **I did not trace the Gateway egress path**, which is the one thing that
  decides its App Store risk.
- **The App Store risk column is my judgement, not a ruling.** For the three I
  marked High — SWARM's background compute donation, CICADA's covert channels,
  and the silent-tone keep-alive — I'd want a second opinion before submission.
- **The dead-code list is reference-based**, so it would miss anything
  constructed dynamically or referenced only from a storyboard. I checked; there
  are no storyboards. But the method has that limit.
- **LOC counts include comments and blank lines.** They measure surface area to
  maintain, not complexity.

---

## The one thing I'd say unprompted

**28% of this codebase is a walkie-talkie and 72% is not.** The crash work is
entirely in the 28%. Every line in the other 72% is a line that has to keep
compiling under Swift 6 strict concurrency, keep passing review, and keep not
leaking, while you fix the part users actually opened the app for.

The features are not bad. Several are genuinely inventive. But they are the
reason the app is 44,000 lines, and the size is the reason the crashes are hard
to find.

**No deletions until you give the cut list.**
