# ChirpChirp — Architecture Audit

**Date:** 2026-07-31
**Scope:** Full read-only audit. No source file was modified.
**Codebase:** 166 Swift files / ~44,100 lines in `Chirp/Sources` (+ 6,555 lines of tests).
**Build config:** iOS 26.0, Swift 6.0, `SWIFT_STRICT_CONCURRENCY: complete`.

---

## Evidence disclosure — read this first

**There are zero crash logs. Anywhere.**

I searched the repo (`*.ips`, `*.crash`, `*.log`, `*.diag`, `*.hang`, `*panic*`),
`/root/Chirp/build/` (contains only `Chirp.ipa` and `Chirp.app.dSYM.zip` from
2026-04-23), and the MacBook: `~/Library/Logs/DiagnosticReports/` (44 entries,
all unrelated system processes), `/Library/Logs/DiagnosticReports/`,
`~/Library/Logs/CoreSimulator/*/CrashReporter/`, and
`~/Library/Developer/Xcode/DerivedData`. `~/Library/Logs/CrashReporter/MobileDevice/`
**does not exist** — no physical-iPhone crash log has ever been ingested on this Mac.
`find ~/Library/Logs -iname '*hirp*'` returns nothing.

**Consequence:** every entry in the crash inventory below is derived from source
reading and git archaeology, not from a captured stack trace. I have labelled
confidence accordingly and I have not upgraded any inference to "Confirmed crash"
without a trace. Where I write **Confirmed**, it means *"I read the code and the
defect is definitely present"* — not *"I have proof this is the crash you saw."*
Those are different claims and I keep them separate throughout.

**Build baseline (established during this audit, 2026-07-31):** the app **builds
successfully** for the iOS 26.2 simulator, Debug configuration, with warnings but
no errors. Two of those warnings independently corroborate findings below:

```
SoundAlertService.swift:39:5: warning: 'nonisolated(unsafe)' has no effect
    on property 'analyzer', consider using 'nonisolated'
SoundAlertService.swift:40:5: warning: 'nonisolated(unsafe)' has no effect
    on property 'analysisRequest', consider using 'nonisolated'
BabelService.swift:376:34: warning: no 'async' operations occur within 'await'
BabelService.swift:376:30: warning: no calls to throwing functions occur within 'try'
```
The first two are the compiler stating outright that 2 of the 14
`nonisolated(unsafe)` annotations are **inert** — they were applied to properties
where they do nothing, which means whatever race motivated them is still
unaddressed. The second pair is a `try? await` on a call that is neither throwing
nor async — a hatch applied to a non-problem.

**A tooling note — CORRECTED 2026-07-31.** An earlier revision of this document
claimed `ios build chirp` reported exit code 0 over a failed build. **That was my
error.** I had piped the command into `tail`, so the status I read was `tail`'s,
not the build's. Measured properly, `ios build chirp` exits **70** on that
failure — its exit-code propagation was already correct (`bin/ios` uses the
`macbook-tunnel` OpenSSH transport and sets `pipefail`).

The *build failure* was real, though, and had two genuine causes, both now fixed
in `/root/ios-toolkit/bin/ios`:
1. The wrapper selected the simulator by **name only**. Two iOS runtimes are
   installed (26.2 and 26.5); all devices live under 26.2 and **26.5 is empty**.
   `xcodebuild` resolves a bare name against the newest runtime, finds nothing,
   and fails. It now resolves to a **UDID**.
2. `ssh host 'bash -s' "$a" "$b"` concatenates args into one string that the
   remote shell re-splits, so any value containing a space was truncated —
   `IOS_SIM_DEVICE="iPhone 16 Pro"` arrived as `iPhone`. Args are now
   `printf '%q'`-quoted.

Separately worth knowing, and **verified independently**: Tailscale SSH
(`ssh macbook`) genuinely does discard the remote exit status
(`ssh macbook "exit 7"` → `$? == 0`), while `ssh macbook-tunnel` preserves it
(`→ 7`). That bug class is catalogued across all repos in
`/root/CROSS-REPO-SSH.md` (22 instances, including this repo's `sync.sh`, since
fixed in `4dbc4e7`). `bin/ios` was already on the safe transport; it now also
**refuses** an unsafe `MAC_SSH` override rather than producing unverifiable
results.

The evidence I *do* have:
1. **14 crash/freeze/deadlock-titled commits**, 8 of them clustered on a single
   day (2026-03-28), all in the audio/PTT path, several with detailed root-cause
   commit bodies.
2. **`SESSION_LOG.md`** — 35 fixes across 4 rounds, with rounds explicitly titled
   *"Babel Freeze, WiFi Aware, Force Unwraps"* and *"Crash Hardening & Test Coverage"*.
3. **Live source**, read directly.

**The single most important verification fact:** `SESSION_LOG.md` claims
"218 tests passing / 0 failures". That number cannot have come from the committed
project. `project.yml` defines exactly one scheme (`Chirp`) with `build`, `run`,
and `archive` blocks and **no `test:` block**; the generated
`ChirpChirp.xcodeproj/xcshareddata/xcschemes/Chirp.xcscheme` on the Mac has an
**empty `<Testables>` element** and the string `ChirpTests` appears in it zero
times. `fastlane/report.xml` (the last shipped build, 2026-04-23) shows
`setup_ci → match → xcodegen → build_app → upload_to_testflight` with **no
`run_tests` step**. The 423 test functions in `ChirpTests/` are unreachable from
`xcodebuild` and from the ship pipeline.

---

## A. System map

### A.1 The architecture as actually built

```
                        ┌─────────────────────────────────┐
   @main ChirpApp ──────│  AppState  (@MainActor,          │
   (39 lines, the       │   @Observable, 1208 lines)       │
    ONLY lifecycle      │                                  │
    hook in the app)    │  • owns 40 services (all `let`)  │
                        │  • constructs ~34 of them in     │
                        │    init(), synchronously, before │
                        │    the first frame               │
                        │  • IS the control-plane router:  │
                        │    one ~160-line closure with a  │
                        │    25-arm switch on 4-byte magic │
                        │    prefixes (TXT!/ACK!/KRO!/…)   │
                        │  • wires ~14 onSendPacket        │
                        │    closures, all `try?`          │
                        │  • registers 8 NotificationCenter│
                        │    observers (a 2nd, untyped,    │
                        │    parallel event bus)           │
                        └───────────────┬─────────────────┘
                                        │ .environment(appState)
                    ┌───────────────────┴────────────────────┐
                    │  60 View files / 22,447 lines          │
                    │  HomeView 1691, MeshMapView 1176,      │
                    │  ChannelView 1174, SettingsView 1149   │
                    │  Views read services DIRECTLY —        │
                    │  no view models between them           │
                    └────────────────────────────────────────┘
```

There is **no layering boundary** between transport, audio, session management,
and UI. `AppState` is simultaneously the composition root, the dependency
container, the packet dispatcher, the permission model, the persistence layer for
identity, and the view model for every screen. Views reach through it into
concrete service types.

### A.2 Isolation model — who is what

| Kind | Count | Members |
|---|---|---|
| `actor` | **6** | `MeshRouter`, `PeerTracker`, `MeshIntelligence`, `PositioningEngine`, `PeerIdentity`, `BackupChunkStore` |
| `@MainActor final class` | **~44** | Nearly every other service |
| `@unchecked Sendable` (deliberately **outside** isolation) | **5** | `AudioEngine`, `OpusCodec`, `JitterBuffer`, `MultipeerTransport`, `AudioStego.TimingDecoder` |
| Static `enum` namespaces | several | `AudioSessionManager`, `TransportPreference`, `ChannelCrypto`, stego types |

**The critical observation:** all 6 actors are *pure logic or storage*. **Not one
of them touches hardware.** And the 5 types that opted *out* of isolation are
precisely the audio pipeline and the Multipeer transport — i.e. the entire
historical crash surface. The concurrency model is inverted: isolation was
applied where it was easy and abandoned where it was needed.

### A.3 Where the structure drifted from the apparent intent

1. **`AudioSessionManager` was meant to be the arbiter of `AVAudioSession`.**
   It is a stateless `enum` of static functions with no ownership, no state, and
   no arbitration. Any component can and does reconfigure the shared session
   behind its back — this already caused one crash class (commit `b45f0c5`,
   `SoundEffects` resetting the category), which was "fixed" by deleting the
   entire tone-synthesis subsystem rather than by giving the session an owner.
   The same class of bug is live again today (see **B-1**).

2. **`PeerTracker` (an actor) looks like the peer-state owner.** It isn't.
   Peer state lives in **four** places simultaneously and nothing reconciles them
   (see **C.1**).

3. **`MeshRouter` looks like the packet-routing layer.** It handles dedup, TTL,
   and forwarding — but *dispatch* (deciding what a packet means) lives in a
   25-arm string switch inside `AppState`, so the router is a hop counter and
   `AppState` is the actual protocol implementation.

4. **`NotificationCenter` is a shadow event bus.** Eight observers in `AppState`
   receive `Data` in `userInfo["packet"]` and forward it to both transports,
   in parallel with the closure-wiring graph. Two mechanisms do the same job.

5. **Teardown is dead code.** `AppState.stop()` (line 1034) — which removes all
   8 observers, cancels tasks, stops the PTT engine, the shield, the BLE scanner,
   and the sound-alert service — **has zero callers in the entire repository**
   (verified by grep across `Chirp/` and `ChirpTests/`). Every "cleanup" fix from
   Round 3 of `SESSION_LOG.md` is unreachable.

6. **No protocols.** `grep -rE "^\s*(public |internal |private |fileprivate )?protocol "` over
   `Chirp/Sources` returns **0 matches across 44,088 lines.** There is not one
   abstraction seam in the codebase. This is why nothing in the crash surface can
   be tested (see **E**).

---

## B. Crash inventory

Ordered by my estimate of severity × likelihood. **No stack traces exist** — see
the evidence disclosure. "Confirmed" = the defect is definitely in the code;
it does not mean the crash is proven to be the one observed on device.

---

### B-1 · PTT dies permanently after the first background→foreground round trip

| | |
|---|---|
| **Symptom** | User backgrounds the app (or locks the phone), returns, and push-to-talk no longer captures audio. No error, no alert. Survives until force-quit and relaunch. |
| **Location** | `Services/BackgroundMeshService.swift:93` (the deactivation) ↔ `Services/Audio/AudioSessionManager.swift:25-45` (the only configuration site) |
| **Root cause — broken invariant** | *"The `AVAudioSession` is configured and active for as long as the PTT engine is alive."* Nothing enforces this. `AudioSessionManager.configure()` is called from **exactly one place** — `AudioEngine.setup()` (`AudioEngine.swift:60`) ← `PTTEngine.start()` (`PTTEngine.swift:162`) ← `AppState.start()`, which runs **once**, at launch, from `.task`. But `BackgroundMeshService.stopSilentAudio()` calls `try? session.setActive(false, options: .notifyOthersOnDeactivation)` on **every** foreground transition (`ChirpApp.swift:28` → `enterForeground()` → `stopSilentAudio()`). Nothing on the foreground path ever reconfigures or reactivates the session. The keep-alive subsystem and the PTT subsystem share one global mutable resource with no owner and no arbitration. |
| **Blast radius** | Every audio feature after one background cycle: PTT capture, playback, voice notes, live transcription, sound alerts. Also the reason the `try?` matters — `setActive(false)` failing is invisible, and so is the fact that it succeeded when it shouldn't have. |
| **Confidence** | **Confirmed as a code defect** — I traced every caller of `configure()` and `setActive()`. The exact runtime symptom (silent failure vs. thrown error from the engine) is **Likely**, not measured. |

---

### B-2 · Stuck microphone + permanently dead PTT button after a floor collision

| | |
|---|---|
| **Symptom** | Two people press talk at nearly the same moment. The loser's UI switches to "receiving", **but their mic keeps transmitting**, and their talk button stops responding to every future press. Recovers only after the 120-second watchdog, or app restart. |
| **Location** | `Services/PTT/FloorController.swift:113-125` → `Views/Components/PTTButtonView.swift:265, 272-286, 339-362` |
| **Root cause — broken invariant** | *"`PTTEngine.isTransmitting` and `FloorController.state` never disagree."* There is no linkage enforcing it. When a remote peer wins a floor collision, `handleRemoteFloorRequest` sets `state = .receiving(...)` directly and **never calls `PTTEngine.stopTransmitting()`**. `FloorController.state`'s `didSet` fires `onStateChange`, whose *only* consumer is `AppState.swift:602` (which feeds `LiveTranscription`) — `PTTEngine` does not observe it at all. `PTTEngine` only stops on: user press-up, audio interruption (`:132`), input-device loss (`:150`), and the 120 s watchdog (`:205`). So `AudioEngine.isCapturing` stays `true`: mic hot, Opus encoding, packets on the wire, while the local UI says someone else is speaking. Compounding it: `PTTButtonView` applies `.allowsHitTesting(canInteract)` (`:265`) and `canInteract` is `false` for `.receiving` (`:64-71`) — the gesture is torn out from under an *in-flight* drag, so `.onEnded` (`:280`) may never fire, leaving `@State isPressed == true`. `handleStateChange` (`:339-362`) only drives animations and never resets it. The next press hits `guard canInteract, !isPressed` (`:274`) and returns forever. |
| **Blast radius** | Any multi-peer session. The 120 s transmit watchdog (`PTTEngine.swift:202-206`) is itself a band-aid added in `SESSION_LOG.md` Round 1 A2 — it exists *because* of this defect and is the only thing that recovers from it. |
| **Confidence** | The floor/engine desync is **Confirmed** (traced all `stopTransmitting()` callers and all `onStateChange` consumers). The stuck `isPressed` is **Likely** — it depends on SwiftUI's gesture-cancellation behaviour when `allowsHitTesting` flips mid-drag, which I reasoned about but did not observe at runtime. |

---

### B-3 · Audio tap buffer escapes the render thread (use-after-recycle)

| | |
|---|---|
| **Symptom** | Non-deterministic. Garbled/robotic audio at best; crash inside CoreAudio or `AVAudioConverter` under sustained transmission at worst. |
| **Location** | `Services/Audio/AudioEngine.swift:137-170`, and two mirrors: `ViewModels/AppState.swift:567-570`, `Services/Protect/SoundAlertService.swift:136-166` |
| **Root cause — broken invariant** | *"An `AVAudioPCMBuffer` delivered to an `installTap` block is valid only for the duration of that block"* — this is AVAudioEngine's contract, and the code violates it in three places. `AudioEngine.swift:150-151` does `nonisolated(unsafe) let buf = buffer; self.processingQueue.async { … self.processInputBuffer(buf) }`. The ObjC object is retained by the closure, so it will not be deallocated — but the *sample memory it wraps* is engine-owned and recycled for the next callback. By the time `processingQueue` drains, the conversion reads samples that the render thread has already overwritten. The comment at `:149` — *"AVAudioPCMBuffer is not Sendable but is only read on processingQueue"* — justifies the escape hatch on **isolation** grounds when the actual hazard is **lifetime**. That is the shape of the whole file: the invariant asserted in the comment is not the invariant that matters. |
| **Blast radius** | Three independent consumers of the same tap buffer, all with the same bug: the Opus encode path, `BabelService.feedLocalAudio` → `SFSpeechAudioBufferRecognitionRequest.append` (`BabelService.swift:223-226`), and `SNAudioStreamAnalyzer.analyze` (`SoundAlertService.swift:139`). Speech and SoundAnalysis both retain buffers internally, widening the window. |
| **Confidence** | The escape is **Confirmed** by reading. That it aliases recycled memory in practice is **Likely** — it follows from AVAudioEngine's documented contract but cannot be proven from source alone. Prior art in this exact file (`c2c7c52`, "*ROOT CAUSE: converter.convert() was running on the audio render thread*") shows the file has a history of exactly this class of error. |

---

### B-4 · Unsynchronized `isCapturing` / `converter` across three threads

| | |
|---|---|
| **Symptom** | Crash or deadlock on rapid press–release–press of the talk button; historically observed as "freeze on PTT release". |
| **Location** | `Services/Audio/AudioEngine.swift:28` (`isCapturing`), `:135`/`:156-158` (`converter`), read at `:139` (render thread) and `:152` (processing queue), written at `:125`/`:179` (MainActor) |
| **Root cause — broken invariant** | *"`isCapturing` is the single authority on whether the tap is live."* It is a plain `Bool` on an `@unchecked Sendable` class, read from the real-time render thread and the processing queue while written from the main actor, with no atomic, no lock, and no memory barrier. `converter` has the identical problem: nil'd on one thread, lazily constructed on another. There is no `stopping` state, so `startCapture()` can re-`installTap` while an in-flight `processingQueue` block still holds the previous converter. |
| **Blast radius** | This flag *is* the start/stop state machine for the whole capture path. It is also the band-aid from commit `0629202` ("*sets isCapturing=false … BEFORE calling removeTap(), preventing deadlock*") — which shipped **two hours before** the real fix `c2c7c52` moved conversion off the render thread, and was then left in place. |
| **Confidence** | **Confirmed** as an unsynchronized cross-thread access. Whether it currently traps is **Speculative** — the window is narrow and the historical deadlock it was written for has since been addressed differently. |

---

### B-5 · Data race on `MultipeerTransport` reconnect state

| | |
|---|---|
| **Symptom** | Non-deterministic; corrupted reconnect counters, duplicate advertiser/browser restarts, potential crash in `MCNearbyServiceAdvertiser`. |
| **Location** | `Services/Network/MultipeerTransport.swift:263-308` (background `Task`) vs `:227-244` (MainActor hop) vs `:97-107` (`stop()`) |
| **Root cause — broken invariant** | The class doc-comment (`:12-15`) asserts *"Mutable state … is dispatched to main queue via `updatePeerList()` to prevent data races"*. `updatePeerList()` (`:215-245`) honours it correctly — nothing mutable is touched before the `Task { @MainActor }` hop. But `startReconnectLoop()` (`:259`) is **nonisolated**, so its `Task` (`:263`) inherits no actor context and runs on the global executor while reading *and writing* the same fields: `reconnectAttempt` at `:266`, `:267`, `:286` races the MainActor write at `:240`; `reconnectTask` at `:260` races `:238-239`; `advertiser`/`browser` are restarted at `:281-284` off-main. `@unchecked Sendable` (`:16`) is why the compiler is silent. Note the comment names `reconnectBackoff` — **a field that does not exist on this type** — and omits `reconnectAttempt`, the field that actually races. |
| **Blast radius** | `stop()` is also nonisolated and mutates the same three fields; `HomeView.swift:1653-1655` calls `stop(); start()` from pull-to-refresh, which can interleave with a live reconnect loop calling `startAdvertisingPeer()`. |
| **Confidence** | **Confirmed** as a data race by reading. Crash attribution: **Speculative** — races of this shape usually corrupt state rather than trap. |

---

### B-6 · Misaligned `load(as:)` on peer-controlled data — an incomplete prior fix

| | |
|---|---|
| **Symptom** | `Fatal error: load from misaligned raw pointer`. Triggerable by a remote peer. |
| **Location** | `Services/PTT/ChannelManager.swift:240`, `Services/Security/ChannelCrypto.swift:109`, `Services/VoiceMessageQueue.swift:236, 271, 281` |
| **Root cause — broken invariant** | *"A `Data` slice's base address is suitably aligned for `load(as: UInt32.self)`."* It is not — `Data` slices carry an arbitrary `startIndex` and no alignment guarantee. Commit `26151b4` ("*Fix misaligned pointer crashes in packet deserialization … crashed the test runner*") fixed exactly this in `MeshPacket`, `AudioPacket`, and `MeshFileTransfer` by rewriting to byte-by-byte reads. **Five sites in three other files were missed.** |
| **Blast radius** | `ChannelManager.swift:240` parses the epoch from every `"KRO!"` key-rotation packet, reached from `AppState.swift:750` — **remote-triggerable from any peer**. `ChannelCrypto.swift:109` is on the decrypt path for every encrypted text message. Worse: the fuzz suite (`DeserializationFuzzTests.swift`) covers 15 magic prefixes but **not `KRO!`** — the one still holding the defect. |
| **Confidence** | **Confirmed** — same construct, same data shape, same file family as an already-proven crash. This is the strongest crash candidate in the audit that has a documented precedent. |

---

### B-7 · `MainActor.assumeIsolated` traps on framework callback threads

| | |
|---|---|
| **Symptom** | Immediate hard trap if the assumption is wrong. |
| **Location** | `Services/Audio/AudioSessionManager.swift:94, 148`; `Services/Security/DarkroomRenderer.swift:231`; `Services/OfflineMapManager.swift:103`; `ViewModels/AppState.swift:941` |
| **Root cause — broken invariant** | `assumeIsolated` converts "I believe this runs on main" into a runtime precondition. The two audio sites sit on the **interruption** and **route-change** handlers — the phone-call-mid-transmission and AirPods-unplug paths. They are registered with `queue: .main` (`:63`, `:71`), which makes the assumption *currently* sound, so this is a latent hazard rather than a live bug. `DarkroomRenderer.swift:231` is the riskiest: it is inside `nonisolated func draw(in: MTKView)`, a **Metal render callback**, where main-thread delivery is a property of how the view is driven, not a guarantee. |
| **Blast radius** | 5 sites; the two audio ones are on the exact paths flagged as unhardened in `CHIRPCHIRP_V2_PLAN.md:237`. |
| **Confidence** | **Speculative** as a live crash. **Confirmed** as an unenforced assumption backed by a trap. |

---

### B-8 · Unhardened `AVAudioFormat(...)!` in `OpusCodec`

| | |
|---|---|
| **Symptom** | Trap at codec construction. |
| **Location** | `Services/Audio/OpusCodec.swift:56` |
| **Root cause** | `SESSION_LOG.md` Round 4 hardened the *identical* construction in `AudioEngine.swift:41-56` to guard-let with a fallback chain. `OpusCodec.swift:56` — the same `AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate:…, channels:…, interleaved: true)!` — was missed. |
| **Blast radius** | One site, but on the PTT startup path. |
| **Confidence** | **Confirmed** as an unhardened force-unwrap; **Speculative** as a crash (the initializer is unlikely to fail for these constants — which is also exactly what was said about the site that *was* hardened). |

---

### B-9 · `peerLeave` control messages are never actually sent

| | |
|---|---|
| **Symptom** | Not a crash — a correctness defect that manifests as ghost peers in the UI. |
| **Location** | `Services/Network/MultipeerTransport.swift:328-335`, `:145-166` |
| **Root cause — two stacked bugs** | (a) **Wrong subject.** On any *remote* peer disconnecting, this device broadcasts `.peerLeave(peerID: localPeerID)` — announcing that **it** is leaving. In a 3+ device mesh, one peer dropping makes the survivors mark each other dead. (b) **Never delivered anyway.** `sendControl` guards synchronously on `!session.connectedPeers.isEmpty` (`:146`) but performs the send inside a `Task` that re-reads `self.session.connectedPeers` *after* an `await` (`:161`). When the last peer drops, that set is already empty on resume, so the message is silently dropped. Both failures are hidden by `try?` at `:330` and `:332`. |
| **Confidence** | **Confirmed** by reading both paths. |

---

## C. Domain-specific review

### C.1 Peer lifecycle

**There is no peer state machine.** `ChirpPeer` (`Models/ChirpPeer.swift:3-16`)
models a peer as `id: String`, `name`, `isConnected: Bool`, `signalStrength: Int`,
`lastHeartbeat: Date`. A grep for peer-state enums across the tree returns only
`PTTState`, `DeliveryStatus`, `BluetoothState`, and a UI-only enum in
`StatusPillView.swift:4`. States like *discovered*, *inviting*, *connecting*,
*degraded* are not representable; there is nowhere to hang the legality of a
transition, so there are no illegal transitions — only inconsistent ones.

**Peer state has four owners and no reconciliation:**

| # | Owner | Isolation | Mutation sites |
|---|---|---|---|
| 1 | `MultipeerTransport.peers` (`:27`) | none (`@unchecked Sendable`) | `:229` (MainActor hop), `:103` (`stop()`, nonisolated) |
| 2 | `WiFiAwareTransport.peers` / `activePeers` / `linkMetrics` | `@MainActor` | `:441`, `:126`, `:278`, `:283`, `:124-125`, `:426`, `:432`, `:129` |
| 3 | `PeerTracker.peers` (`PeerTracker.swift:6`) | **`actor`** ✔ | `:26`, `:36`, `:42`, `:51`, `:91`, `:96` |
| 4 | `ChannelManager.channels[i].peers` | `@MainActor` | `:70`, `:111`, `:119`, `:257`, `:289` |

`AppState.updateUnifiedPeerList()` (`:1085-1157`) merges **only #1 and #2**, then
tears down and rebuilds the entire channel peer list on every peer event
(`:1121-1127`) — thrashing `@Observable` and invalidating SwiftUI on every
join/leave. **`PeerTracker` — the one correctly-isolated owner — is never
consulted by the merge.** Its ghost-detection callback (`AppState.swift:339-345`)
just calls `updateUnifiedPeerList()`, which re-reads the two transports. So a peer
that `PeerTracker` has marked ghosted stays in the UI list as long as MCSession
still reports it connected. The "peer ghosting detection" feature (commit
`9129400`) is wired to a function that ignores its result.

**Three incompatible identity namespaces:**
- MultipeerConnectivity: `id = mcPeer.displayName` (`:220`), where `displayName`
  comes from the user's mutable callsign (`AppState.swift:322`).
- Wi-Fi Aware: `"wa-in-\(UUID().prefix(8))"` / `"wa-out-…"`, minted **per
  connection** (`WiFiAwareTransport.swift:177`, `:229`).
- Mesh control plane: the stable `localPeerID` UUID carried in `peerJoin`/heartbeat.

Consequences: `transportType == .both` is essentially unreachable, so
`TransportPreference.shouldSendOnWA/shouldSendOnMC` routes on a distorted picture;
a reconnected Wi-Fi Aware peer is always a brand-new identity; and
`AppState.swift:795` passes a *Multipeer displayName* as the `excludePeer`
argument to the *Wi-Fi Aware* transport, where it can never match.

**Simultaneous mutual invitation is unhandled.** `browser(_:foundPeer:)`
(`:379-383`) invites **every** peer it finds; `advertiser(_:didReceiveInvitation…)`
(`:366-369`) **auto-accepts everything**, with `context: nil`. There is no
tie-break of any kind — no ID comparison, no "only invite if I sort lower". Both
devices advertise and browse simultaneously (`start()`, `:76-95`). This is the
textbook configuration for connect/disconnect flapping, and it is almost certainly
what the exponential-backoff reconnect machinery (commit `283f689`) was built to
compensate for.

**Stale peer IDs.** `MCPeerID` is constructed fresh in `init` (`:59`) and never
archived — there is no `NSKeyedArchiver` around `MCPeerID` anywhere. Apple's
guidance is to persist and reuse it. A peer that relaunches presents a *different*
`MCPeerID` with the same `displayName`; a peer that changes callsign forks its
identity while its mesh `localPeerID` stays stable.

**Rapid flapping.** `browser(_:lostPeer:)` (`:385-387`) **only logs** — it does
not touch `peers`, does not mark anything disconnected, does not call
`updatePeerList()`. Peer loss is only observed indirectly via
`session.connectedPeers` changing.

### C.2 Threading and isolation

**Callback queues, as actually delivered:**

| Source | Arrives on | Handling |
|---|---|---|
| `MCSessionDelegate` (all methods) | MultipeerConnectivity's **private internal queue** | No `nonisolated`/`@MainActor` markers — the class carries no isolation at all. `updatePeerList()` hops correctly; `startReconnectLoop()` does not (**B-5**) |
| `MCNearbyServiceAdvertiser/Browser` delegates | same private queue | `invitationHandler(true, session)` called inline |
| Wi-Fi Aware (`NetworkListener`/`NetworkBrowser`/`NetworkConnection` async sequences) | **MainActor** | Every `Task` is created inside a `@MainActor` method and inherits it |
| `AVAudioEngine` `installTap` | **real-time render thread** | Three contract violations (**B-3**, **B-4**) |
| `AVAudioSession` interruption / route change | `.main` (registered with `queue: .main`) | `MainActor.assumeIsolated` (**B-7**) |
| CoreBluetooth (`BLEScanner`) | delegate queue | Correctly `nonisolated` + `Task { @MainActor [weak self] }` — **this is the file that does it right** (`BLEScanner.swift:258, 286, 260, 310`) |

**`BLEScanner` is the reference implementation the transport layer should have
followed.** It is `@MainActor final class` with explicitly `nonisolated` delegate
methods that hop. `MultipeerTransport` took the opposite path — no isolation plus
`@unchecked Sendable` — and that is the difference between the two files' defect counts.

**Wi-Fi Aware has the opposite problem:** it is *fully* `@MainActor`, which means
the inbound receive loop, TLV decode, and every `broadcastToAll` run on the main
thread (`WiFiAwareTransport.swift:266-280`, `:389-393`). No races — but every
audio packet is decoded on the UI thread. The two transports are structurally
asymmetric in a way nothing documents.

**Strict concurrency is already ON.** `project.yml:19-20`:
`SWIFT_VERSION: '6.0'`, `SWIFT_STRICT_CONCURRENCY: complete`, with **no**
`SWIFT_UPCOMING_FEATURE_*` or `OTHER_SWIFT_FLAGS` anywhere. So the answer to
*"what breaks when it is turned on"* is: **it is on, and what broke was suppressed
rather than fixed.** The suppression inventory:

| Hatch | Count | Where it matters |
|---|---|---|
| `@unchecked Sendable` | 5 (+1 in tests) | `AudioEngine`, `OpusCodec`, `JitterBuffer`, `MultipeerTransport`, `AudioStego.TimingDecoder` — the entire crash surface |
| `nonisolated(unsafe)` | 14 | `AudioEngine` ×4, `SoundAlertService` ×4, `DarkroomRenderer` ×2 (stored raw pointer + size — the only tearable pair), `AppState`, `BabelService`, `ChorusService`, `OfflineMapManager` |
| `@preconcurrency import` | 7 | AVFoundation, Speech ×2, Opus, MapLibre ×3 |
| `MainActor.assumeIsolated` | 5 | **B-7** |
| `try?` | 230 | 38 in `AppState.swift` alone |

Clean by contrast, and worth stating: **zero** `try!`, **zero** `as!`, **zero**
`precondition`/`assert`, **zero** `Task.detached`, **zero** `DispatchQueue.*.sync`,
**zero** `objc_sync`, **zero** truly empty `catch {}` blocks (I verified this two
ways — every `catch` in `Services/` logs). Only 2 `fatalError`s, one of them
unreachable boilerplate. The error-*logging* hygiene is genuinely good; the
error-*handling* hygiene is not, because `try?` bypasses the logging entirely.

### C.3 Audio

**Session configuration** (`AudioSessionManager.swift:32-40`) is correct for PTT:
`.playAndRecord`, mode `.voiceChat` (hardware AEC/AGC/NS), options
`[.defaultToSpeaker, .allowBluetoothHFP]`, 10 ms preferred IO buffer, 16 kHz
preferred rate. No complaints about the parameters. The problem is ownership, not
values — see **B-1**.

**Interruption handling: present.** `:63-69` observer, handled `:84-114`;
`PTTEngine.swift:128-145` stops transmitting on `.began` and calls
`restartEngineIfNeeded()` on `.ended` with `.shouldResume`.

**Route-change handling: present.** `:71-77`, handled `:118-152`;
`.oldDeviceUnavailable` → `onInputDeviceLost` → `stopTransmitting()`
(`PTTEngine.swift:146-152`). AirPods disconnecting mid-transmission is handled.

**`AVAudioEngineConfigurationChange`: MISSING.** A repo-wide grep for
`ConfigurationChange` returns only a `case .routeConfigurationChange` string
label. There is no observer for
`AVAudioEngineConfigurationChangeNotification`. When the hardware format changes
underneath a running engine — the exact scenario when a route switches — nothing
re-installs the tap or reconnects the player node. The only recovery is
`restartEngineIfNeeded()` (`AudioEngine.swift:104`), reachable *only* from the
interruption-ended callback. **This is the single clearest missing piece of the
audio subsystem**, and it is a plausible root cause for the "3rd PTT press"
family of crashes that were instead patched by passing `nil` formats.

**Observer registration is not idempotent.** `registerForNotifications()`
(`:59+`, called from `AppState.swift:820`) has no guard, and the returned
observer tokens are discarded — they can never be removed. Calling it twice
silently doubles every interruption handler.

**Buffer lifetime and ownership across the pipeline:**
- Capture → encode: **broken** (**B-3**).
- Sample extraction is otherwise careful — `AudioEngine.swift:380`/`:386` copy via
  `Array(UnsafeBufferPointer(...))`, `:283-288` keeps `withUnsafeBytes` scoped,
  `JitterBuffer.swift:136` uses `Data(bytes:count:)`. No `Data(bytesNoCopy:)`
  anywhere. No manual `UnsafeMutablePointer` allocation.
- One surviving force-unwrap on the playback path: `AudioEngine.swift:412`
  `dest[0].update(from: src.baseAddress!, …)`.
- `DarkroomRenderer.swift:30-31` is the one genuinely dangerous stored-pointer
  pair: `nonisolated(unsafe) private var pixelBufferPointer: UnsafeMutableRawPointer?`
  alongside `pixelBufferSize: Int` — two independently-mutable fields that must
  agree, with no synchronization. A torn read here is a wild pointer.

**Codec:** encoder is C `libopus` via a hand-written shim (`opus_ctl_shim.c`,
hardcoding CTL request numbers 4002/4003/4012/4014); decoder is the Swift `Opus`
wrapper. `OpusCodec` is `@unchecked Sendable` with **no lock**, but the two
handles happen to be confined to different executors (encoder →
`processingQueue`, decoder → MainActor), so I found **no shared-handle race**.
That is an accident of current call sites, not an enforced invariant.

**Allocation churn on the real-time path:** a fresh `AVAudioPCMBuffer` *and* a
fresh `AVAudioFormat` per 20 ms playback frame (`AudioEngine.swift:269, 276-279`),
plus `[UInt8](repeating: 0, count: 4000)` per encode (`OpusCodec.swift:133`) —
~50 allocations/sec each on latency-sensitive paths.

**PushToTalk.framework is not used.** Zero hits for `PushToTalk`/`PTChannelManager`.
This is a custom SwiftUI button, which means no system PTT UI and — importantly —
**no background PTT activation**, regardless of what `UIBackgroundModes` claims.

### C.4 Backgrounding and lifecycle

`ChirpApp.swift` is 39 lines and contains the **only** lifecycle hook in the app.
There are **no** `UIApplication.didEnterBackgroundNotification`,
`willResignActive`, `willEnterForeground`, or `didBecomeActive` observers anywhere.

- **On background:** nothing is torn down. `enterBackground()`
  (`BackgroundMeshService.swift:29-36`) only *adds* work — a silent-audio
  keep-alive and a `beginBackgroundTask`. Transports, advertiser, browser,
  MCSession, BLE scanner, location, and every timer keep running.
- **On foreground:** nothing is rebuilt, and the audio session is **deactivated**
  (**B-1**).
- **On termination / suspension:** no handling at all. `AppState.stop()` is dead code.
- **Advertiser/browser duplication:** `start()` (`:76-92`) allocates new
  advertiser and browser objects with no `guard advertiser == nil`. Currently safe
  only because the two call sites (`AppState.start()`, and `HomeView.swift:1653-1655`
  pull-to-refresh) happen to call `stop()` first. Nothing enforces it.
- **Background modes claimed vs. used:** `UIBackgroundModes` contains **`audio`
  only**. But `BGTaskScheduler` registers `com.chirpchirp.mesh.refresh` as a
  `BGAppRefreshTask` (`BackgroundMeshService.swift:52-62`) and
  `com.chirpchirp.swarm.compute` as a `BGProcessingTask` (`SwarmService.swift:141-145`).
  Without `fetch` and `processing` in `UIBackgroundModes`, **neither task can ever
  be launched by the system.** Likewise MultipeerConnectivity does not survive
  backgrounding on `audio` alone, so the mesh keep-alive rests entirely on the
  inaudible 20 Hz / −60 dB tone (`:99-135`) — which is exactly the pattern App
  Review rejects (see **C.7**).
- **Crash recovery:** `CHIRPCHIRP_V2_PLAN.md:245` specifies persisting the active
  channel and auto-rejoining after a crash or force-quit. Not implemented.

### C.5 Memory

**Retain cycle (confirmed):** `MultipeerTransport` holds `let meshRouter: MeshRouter`
strongly (`:47`), and `AppState.swift:790-797` installs `router.setCallbacks(onForward:)`
whose closure captures `mpTransport` strongly. **MeshRouter ⇄ MultipeerTransport.**
Both are app-lifetime singletons, so this is permanent retention rather than a
growing leak — but it means neither can ever be torn down and rebuilt, which
forecloses the obvious fix for several defects above.

Other strong captures in long-lived closures: `AppState.swift:597-599` and
`:602-611` capture `LiveTranscription`; `:381-384` captures both transports;
`:556-560` captures `positioningEngine`. Everything else in `AppState.init` uses
`[weak self]` consistently (121 `[weak self]` occurrences tree-wide) — the
discipline is mostly good, with these specific gaps.

**Observers never removed:** `AudioSessionManager.swift:63, 71` (tokens
discarded, no removal path exists) and `SoundAlertService.swift:83`.
`AppState`'s 8 observers *are* collected and removed — in `stop()`, which is never
called.

**Unbounded collections** (verified by searching for the corresponding prune/trim):

| Collection | Location | Why it grows forever |
|---|---|---|
| `GatewayDeliveryService.deliveryStatuses` | `:34` | written at `:65,69,73,77,194`; never removed, no cap |
| `StoreAndForwardRelay.pendingMessages` | `:11` | `pruneExpired()` exists at `:63` — **zero call sites** |
| `MeshGateway.knownGateways` | `:58` | `pruneStaleGateways()` at `:345` — **zero call sites** |
| `VoiceMessageQueue.receivedMessages` | `:39` | `insert(at: 0)` at `:219`; `pruneDelivered()` at `:316` — **zero call sites**, and it only filters a *different* array anyway |
| `DeadDropService` / `DarkroomService` | `:202` / `:211` | `pruneExpired()` defined in both — **zero call sites** |
| `SwarmService.completedUnits`, `knownNodes` | `:24`, `:25` | siblings are cleaned at `:279-280`; these two are not |
| `ChorusService.activePipelines`, `peerOffers` | `:26-27` | no prune found |
| `BLEScanner.deviceMap` / `discoveredDevices` | `:49`, `:18` | one entry per unique peripheral ever seen, plus peers' merged scan reports (`:242-243`) |
| `AudioEngine.captureAccumulator` | `:25` | drained per frame at `:399-401`, but the `guard let codec else { return }` at `:417` returns **before** draining — if the codec is nil, it grows without bound while frames keep arriving |

**The pattern is striking:** six `pruneX()` functions exist, are correct, and are
never called. Someone wrote the cleanup and never wired it.

Properly bounded, for contrast: `MeshRouter.seenPackets` (10 000),
`TextMessageService` (200/channel, actually pruned), `PheromoneRouter.forwardedACKs`
(500), `EmergencyBeacon.receivedAlerts` (50), `SoundAlertService` (50),
`PrivacyShield` (20), `LiveTranscription` (50), `ProximityAlert` (5),
`MeshBeacon.knownNodes`, `MeshIntelligence`, `JitterBuffer`.

Only **3 `deinit`s** across 64 service files.

### C.6 Error and permission paths

**Well-handled:** microphone permission has a real model —
`AppState.PermissionDeniedAlert` (`:82-107`) with titles/messages for microphone,
location, and camera, plus `openAppSettings()`. Bluetooth state is modelled
(`BLEScanner.BluetoothState`). Network path changes are monitored via `NWPathMonitor`
(`MeshGateway.swift:122`).

**Not handled — each of these currently produces a silent no-op rather than a
defined user-visible state:**

| Condition | Current behaviour |
|---|---|
| **Local network permission denied** | No detection anywhere. `NSLocalNetworkUsageDescription` is declared, but nothing observes the denial. Advertising/browsing fail silently — `didNotStartAdvertisingPeer` (`:371-373`) and `didNotStartBrowsingForPeers` (`:389-391`) **only log**. The user sees "no peers found", forever, with no explanation. This is the single worst permission gap. |
| **Wi-Fi off / airplane mode** | Not surfaced. `WiFiAwareTransport` retries silently (max 3, then stops). |
| **Bluetooth off** | Modelled in `BLEScanner` for the Protect feature, but not connected to the mesh transport status. |
| **Permission revoked while running** | No observation of `AVAudioApplication.recordPermission` changes after launch. |
| **Wi-Fi Aware service definitions missing from Info.plist** | `WiFiAwareTransport.swift:156, 204` log *"chirp-ptt publishable/subscribable service not found in Info.plist"* — and indeed **there is no `WiFiAwareServices` key in Info.plist** (it was commented out in `ce5aacf` after a fatal error and never restored). So the entire Wi-Fi Aware transport is dead on arrival at runtime, logging an error nobody reads, while the app carries the `com.apple.developer.wifi-aware` entitlement. |

**The `try?` census, by consequence.** 230 total; the ones that matter most:
- `WiFiAwareTransport.swift:371, 391` — **every outbound Wi-Fi Aware byte** (audio,
  control, files, forwards) discards its send error. A dead link produces no log,
  no peer removal, no metric.
- `AppState.swift` — all ~14 `onSendPacket` closures are `try? transport.sendControlData(...)`.
  **Every control-path send failure in the app is swallowed at the top level.**
- `Security/ChannelCrypto.swift:114-115, 124-125, 131-132` and
  `Security/MeshShield.swift:83-84, 92` — decryption failure (wrong epoch,
  tampering, corruption) is indistinguishable from "no data".
- `Security/PeerIdentity.swift:97, 119` — a corrupt keychain blob silently
  degrades to "no identity", after which a **new key is generated**, changing the
  device's cryptographic identity with no signal to anyone.
- `Persistence/LighthouseDatabase.swift:140, 143` and `MessageDatabase.swift:50, 53`
  — `try? setResourceValues` / `try? setAttributes` set the **file-protection class
  and exclude-from-backup flags** on the encrypted message database. Silent failure
  means the database may be written **without its intended data protection**.
- `AppState.swift:811` — `try? await pttEngine.start()`. A failed PTT engine start
  is discarded on the app's main startup path.
- `AppState.swift:275-289` — `try? LighthouseDatabase()`, retry once, then
  construct `LighthouseService()` **with no database at all**; positioning
  silently no-ops forever behind one log line. This is the shape commit `83befc8`
  installed deliberately ("*fatalError on LighthouseDB → retry once, then no-op fallback*").

### C.7 App Store readiness blockers

**Correct and worth confirming:** `NSBonjourServices` lists `_chirp-ptt._udp` and
`_chirp-ptt._tcp`, which exactly matches `serviceType = "chirp-ptt"` in
`MultipeerTransport.swift:21` (MultipeerConnectivity expands to both). All 12
usage-description strings are present, specific, and plausible.
`ITSAppUsesNonExemptEncryption: false` is set. `PrivacyInfo.xcprivacy` exists and
declares `NSPrivacyTracking: false` with three accessed-API reasons (UserDefaults
`CA92.1`, FileTimestamp `C617.1`, DiskSpace `E174.1`).

**Blockers, ranked:**

1. **Background `audio` mode used for a keep-alive tone.** The app claims only
   `audio` and uses it to play an inaudible 20 Hz / −60 dB tone
   (`BackgroundMeshService.swift:99-135`) whose stated purpose in the source
   comment is *"iOS is less likely to detect 'no audio' and suspend the process"*.
   This is a documented App Review rejection pattern (§2.5.4 — background modes
   used for purposes other than their intended function). **This is the highest
   rejection risk in the project.** For a PTT app the legitimate route is
   PushToTalk.framework with the `push-to-talk` background mode and the
   corresponding entitlement — neither of which the app currently has.
2. **`NSPrivacyCollectedDataTypes` is empty**, but the app handles precise
   location, audio recordings, photos, and user-generated messages. Even if none
   leaves the device, the manifest needs to reflect what is collected. As written
   it is very likely inaccurate.
3. **Declared capabilities the app cannot deliver.**
   `NSLocationAlwaysAndWhenInUseUsageDescription` promises "background location
   for emergency SOS broadcasting", but there is **no `location` background mode**
   — the feature cannot work. Similarly, two `BGTaskSchedulerPermittedIdentifiers`
   are declared and registered with no `fetch`/`processing` background modes.
   Reviewers test Always-location claims.
4. **`com.apple.developer.wifi-aware` entitlement with a non-functional feature.**
   The entitlement is present (`Chirp.entitlements`), but the required
   `WiFiAwareServices` Info.plist key is absent, so the transport fails at
   startup. Also note `project.yml:22` sets `CODE_SIGN_ENTITLEMENTS` in **base**
   settings and the `ChirpLiveActivity` target does not override it — **the widget
   extension inherits the wifi-aware entitlement**, which it does not use and
   which may fail provisioning-profile validation.
5. **`NSSupportsLiveActivities: true` with Live Activities disabled in code.**
   `LiveActivityManager.startActivity` is commented out at its only call site
   (`AppState.swift:864-866`), disabled since commit `0c6ef20` ("*the widget
   extension was failing to load on device, causing SpringBoard to kill the host
   app*"). The extension still ships in the bundle.
6. **`Package.resolved` is gitignored** and `Opus` is pinned `from: 0.0.1` — a
   floating pre-release dependency. Builds are not reproducible; a point release
   of the Opus wrapper can change shipped behaviour with no code change.

---

## D. Remediation plan

> **Product decisions received 2026-07-31 — these override the ranking below.**
>
> - **Background operation: DROPPED for v1.** PushToTalk.framework is not being
>   adopted. Verified against Apple's WWDC22 session: background receive requires
>   a server sending an `apns-push-type: pushtotalk` notification using a token
>   issued at channel join. There is no peer-to-peer path, so a serverless mesh
>   has nothing to send it. Action: delete `BackgroundMeshService` and the
>   silent-tone keep-alive, drop the `audio` background mode if no longer
>   justified, and state in the UI and App Store description that ChirpChirp
>   transmits and receives **while open**. *A future version could do this
>   legitimately only by introducing a relay server + APNs (which abandons the
>   serverless premise), or by keeping the app foregrounded.*
> - **Wi-Fi Aware: CUT for v1.** Remove the entitlement, the transport, and the
>   config; keep the code in git history. Simplifies **D-6**.
> - **Live Activities: REMOVED for v1.** Drop the widget extension, its
>   entitlements, and `NSSupportsLiveActivities`.
> - **Feature surface: cutting is on the table, pending a separate inventory
>   document** (reachable from UI / works / leaks / LOC / does PTT need it /
>   review risk, ranked by cost-to-keep). **No deletion until that list is
>   approved.**
> - **Privacy manifest (was D-14): PROMOTED TO P0 BLOCKER.** On-device-only
>   processing still generally requires declaration.
> - **Failing tests: catalogue, don't fix.** Only fix failures covering audio
>   session, floor control, transport alignment, and buffer lifetime. Everything
>   else is written down and deferred.
> - **Progress metric:** the `nonisolated(unsafe)` count is reported at the top of
>   every session log. It only goes down. **Baseline: 14** (app source).
> - **D-16 (dependency locking): DONE 2026-07-31** — Opus/GRDB/MapLibre pinned to
>   exact versions in `project.yml`. Superseded in priority order to D-0b.

Ranked. Each item is sequential: implement → build clean → test → report → next.

### P0 — crashes and dead-in-the-water defects

**D-1 · Give `AVAudioSession` a single owner** → fixes **B-1**
*If we do nothing:* PTT is silently dead after the first background→foreground
cycle. This is likely the most commonly-hit defect in the entire app, and it
looks to a user like the product simply doesn't work.
*Permanent fix:* Convert `AudioSessionManager` from a stateless static `enum` into
an owned, stateful arbiter (a `@MainActor final class`) that is the **only** type
permitted to call `setCategory`/`setActive`. It tracks reference-counted demand
(PTT active, keep-alive active, voice-note playback) and computes the session
state, so no component can deactivate a session another component still needs.
`BackgroundMeshService` releases its claim instead of calling `setActive(false)`.
*Files:* `Services/Audio/AudioSessionManager.swift` (rewrite, ~150 → ~250 lines),
`Services/BackgroundMeshService.swift`, `Services/Audio/AudioEngine.swift`,
`Utilities/VoiceNoteRecorder.swift`, `Utilities/SoundEffects.swift`.
*Regression risk:* **Medium** — touches every audio entry point.
*Dependencies:* none. **Start here.**

**D-2 · Byte-wise reads for the 5 surviving misaligned `load(as:)` sites** → fixes **B-6**
*If we do nothing:* a remote peer can hard-crash the app with a malformed `KRO!`
packet.
*Permanent fix:* Reuse the existing, already-correct `MeshPacket.readBigEndian`
byte-by-byte helper rather than writing new code; extend the
`DeserializationFuzzTests` corpus to cover `KRO!`, `ACK!`, `RXN!`, and `UWB!`.
*Files:* `ChannelManager.swift:240`, `ChannelCrypto.swift:109`,
`VoiceMessageQueue.swift:236,271,281`, `ChirpTests/DeserializationFuzzTests.swift`.
*Regression risk:* **Low** — mechanical, and the pattern is already proven in-tree.
*Dependencies:* needs **D-8** (tests wired into a scheme) to be verifiable.

**D-3 · Couple `FloorController` and `PTTEngine` into one state machine** → fixes **B-2**
*If we do nothing:* stuck-hot microphone and a permanently dead talk button after
any floor collision; the only recovery is a 120-second watchdog.
*Permanent fix:* `FloorController` becomes the single authority and **drives**
`PTTEngine` — losing the floor calls `stopTransmitting()` as part of the
transition, not as a hoped-for side effect. `PTTButtonView` stops deriving
interactivity from a state that can change mid-gesture: replace
`.allowsHitTesting(canInteract)` with an explicit press-state reset driven from
`handleStateChange`, so `isPressed` cannot survive a state change.
*Files:* `Services/PTT/FloorController.swift`, `Services/PTT/PTTEngine.swift`,
`Views/Components/PTTButtonView.swift`.
*Regression risk:* **Medium** — this is the core interaction of the app.
*Dependencies:* none. Once done, the 120 s watchdog becomes a genuine safety net
rather than the primary recovery path.

**D-4 · Copy tap samples inside the tap; get client code off the render thread** → fixes **B-3**, **B-4**
*If we do nothing:* non-deterministic audio corruption and latent crashes under
sustained transmission.
*Permanent fix:* Inside the tap block, copy samples into a plain `[Int16]`/`Data`
value **synchronously**, then dispatch that value. Nothing that is not `Sendable`
crosses the queue boundary, so all four `nonisolated(unsafe)` sites in the capture
path are **deleted, not annotated**. Replace `isCapturing`/`converter` with a
single state value behind `OSAllocatedUnfairLock` (already used elsewhere in the
codebase — `TransportPreference.swift:41,47`), including an explicit `stopping`
state. Move `onRawAudioBuffer` and `updateInputLevelFromRawBuffer` off the render
thread. Apply the same copy-first treatment to the two mirrors in
`AppState.swift:567` and `SoundAlertService.swift:139`.
*Success criterion:* `@unchecked Sendable` comes **off** `AudioEngine`.
*Files:* `Services/Audio/AudioEngine.swift` (substantial), `ViewModels/AppState.swift`,
`Services/Protect/SoundAlertService.swift`.
*Regression risk:* **High** — this is the hot path. Needs the harness from **E**.
*Dependencies:* **D-1** (session ownership) should land first.

**D-5 · Add the missing `AVAudioEngineConfigurationChange` observer**
*If we do nothing:* route changes that alter the hardware format leave the engine
in a broken state with no recovery — the most credible explanation for the
"3rd PTT press" crash family that was previously patched by passing `nil` formats.
*Permanent fix:* Observe the notification and rebuild the graph (reinstall tap,
reconnect player node) through one `rebuildGraph()` path shared with
`restartEngineIfNeeded()`. Make `registerForNotifications()` idempotent and
retain its tokens.
*Files:* `Services/Audio/AudioSessionManager.swift`, `Services/Audio/AudioEngine.swift`.
*Regression risk:* **Low-Medium**.
*Dependencies:* **D-1**, **D-4**.

### P1 — structural fixes that prevent the next round of crashes

**D-6 · One peer identity, one peer state machine, one owner** → fixes **C.1**
*If we do nothing:* four divergent peer collections and three identity namespaces
guarantee a continuing stream of "ghost peer" and "peer won't reconnect" bugs
that are individually unfixable.
*Permanent fix:* Introduce `PeerConnectionState { discovered, inviting, connecting,
connected, degraded, lost }` with centralized, validated transitions. Make
`PeerTracker` (already correctly an actor) the **single** owner; the transports
report *events* to it and stop holding peer arrays. `MultipeerTransport.peers` and
`ChannelManager.peers` become derived, read-only projections. Unify on the stable
`localPeerID` UUID as the one identity: exchange it in the invitation `context`
(currently `nil`) and in the Wi-Fi Aware handshake, and key every collection on it.
*Files:* new `Models/PeerConnectionState.swift`, `Services/Network/PeerTracker.swift`,
`MultipeerTransport.swift`, `WiFiAwareTransport.swift`, `ChannelManager.swift`,
`AppState.swift:1085-1157`. **Large.**
*Regression risk:* **High** — but this is the fix that makes the others hold.
*Dependencies:* **D-9** (protocol seam) makes this testable; do that first.

**D-7 · Deterministic invitation tie-break; delete the reconnect machinery** → fixes **C.1**, **B-5**
*If we do nothing:* connect/disconnect flapping continues, and the backoff loop
that compensates for it keeps racing its own state.
*Permanent fix:* Exchange stable peer IDs in the invitation `context`; only the
peer whose ID sorts lower invites, the other only accepts. Deduplicate against
already-connected peers. Handle `lostPeer` as a real state transition instead of a
log line. **This should let the exponential-backoff reconnect loop be deleted
rather than tuned** — which removes **B-5**'s data race by removing the racing
code. Convert `MultipeerTransport` to an `actor` with `nonisolated` delegate
funnels (following `BLEScanner`'s pattern) and delete its `@unchecked Sendable`.
Persist and reuse an archived `MCPeerID`. Fix the `peerLeave` subject bug (**B-9**)
and remove the `try?` hiding it.
*Files:* `Services/Network/MultipeerTransport.swift` (**substantial rewrite**).
*Regression risk:* **High**.
*Dependencies:* **D-6**, **D-9**.

> **Honest assessment:** `MultipeerTransport`'s peer-state and reconnection
> handling should be **rebuilt, not repaired.** Between the missing tie-break,
> the no-op `lostPeer`, the unpersisted `MCPeerID`, the racing reconnect loop, the
> wrong-subject `peerLeave`, and the post-`await` re-read in `sendControl`, there
> is no coherent state model to preserve. The MCSession setup, the mesh-magic
> framing, and the send paths are fine and should be kept.

**D-8 · Wire `ChirpTests` into the scheme**
*If we do nothing:* 423 tests and 6,555 lines of test code never run, and no fix
in this plan can be regression-guarded.
*Permanent fix:* Add a `test:` block to the `Chirp` scheme in `project.yml`
listing `ChirpTests`; add `run_tests` to the fastlane ship lane so a red suite
blocks a release.
*Files:* `project.yml`, `fastlane/Fastfile`. **Small.**
*Regression risk:* **Low**, but expect initial failures — the suite has never been
run by CI and its "218 passing" claim is unverified.
*Dependencies:* none. **This is the cheapest high-value item in the plan and
should arguably run first, before D-1.**

**D-9 · Introduce the first protocol seam**
*If we do nothing:* nothing in the crash surface can ever be tested, and every fix
above is verified by hand on a device with no artifact.
*Permanent fix:* Extract a `MeshTransport` protocol (`start`, `stop`, `send`,
`forward`, peer-event stream) implemented by both transports and by a new
`FakeTransport`. This is the first abstraction boundary in the codebase.
*Files:* new `Services/Network/MeshTransport.swift`, both transports,
`AppState.swift` (holds `any MeshTransport`), new `ChirpTests/FakeTransport.swift`.
*Regression risk:* **Medium**.
*Dependencies:* **D-8**.

**D-10 · Call the six orphaned `pruneX()` functions; bound the rest** → fixes **C.5**
*Files:* `StoreAndForwardRelay`, `MeshGateway`, `VoiceMessageQueue`,
`DeadDropService`, `DarkroomService`, `SwarmService`, `ChorusService`,
`GatewayDeliveryService`, `AudioEngine:417`. Mostly wiring existing correct code.
*Regression risk:* **Low**.

**D-11 · Break the `MeshRouter ⇄ MultipeerTransport` cycle; make teardown reachable**
Weaken the `onForward` capture; give `AppState.stop()` a caller (or delete it
honestly rather than leaving dead cleanup code that implies coverage it doesn't have).
*Regression risk:* **Low-Medium**.

**D-12 · Define user-visible states for every failure path** → fixes **C.6**
Local-network-denied is the priority: detect it and surface it, instead of an
eternal "no peers found". Then Wi-Fi off, Bluetooth off, airplane mode, and
mid-session permission revocation. Extend the existing `PermissionDeniedAlert`
model rather than inventing a new one.

### P2 — submission and hygiene

**D-13 · Reconcile background modes with reality.** Either adopt
PushToTalk.framework properly (with the `push-to-talk` background mode and
entitlement) or **remove the inaudible-tone keep-alive** and be honest that the
mesh does not run in the background. Add `fetch`/`processing` if the BG tasks are
to be kept, or remove their registrations. Remove the `location` claim or add the
mode. **This is a product decision, not a technical one — see Q1.**

**D-14 · Privacy manifest and entitlement cleanup.** Populate
`NSPrivacyCollectedDataTypes`. Scope `CODE_SIGN_ENTITLEMENTS` to the app target so
the widget stops inheriting the wifi-aware entitlement. Decide on Live Activities:
enable them or remove `NSSupportsLiveActivities` and the extension.

**D-15 · Restore the `WiFiAwareServices` Info.plist key** so the Wi-Fi Aware
transport can actually initialize, or disable the transport and drop the
entitlement. Currently it is entitled, shipped, and dead.

**D-16 · Commit `Package.resolved`; pin Opus to an exact version.**

**D-17 · Sweep the 230 `try?`.** Each becomes either a handled error or a
`try` with a documented justification. Prioritize: `WiFiAwareTransport` sends,
`AppState`'s 14 control-path closures, the crypto paths, and the two
data-protection-attribute calls.

---

## E. Verification strategy

**The current state, stated plainly:** 423 tests exist, cover pure data
structures well (wire formats, Shamir, geohash, floor-control tie-breaks, jitter
wraparound, a 15-handler fuzz corpus), and **are not wired into any scheme, so
none of them run**. `AudioEngine`, `PTTEngine`, `OpusCodec`, `MultipeerTransport`,
`WiFiAwareTransport`, and `AppState` are instantiated by **zero** tests. The
entire historical crash surface has no coverage, and — with zero protocols in
44 kLOC — cannot be given any without a refactor. Every past fix was validated by
hand on a device and no artifact of that validation survives.

**What I established during this audit:** the app builds clean (warnings only)
against the iOS 26.2 simulator. I could **not** run the test suite, because it is
not in any scheme — that is **D-8**, and it is a precondition for every other
verification claim here. I also could not run anything on physical hardware.

**What we build, in order:**

0. ~~Fix the `ios build` wrapper's exit code.~~ **Withdrawn — the premise was my
   error; see the corrected tooling note at the top.** The wrapper's exit code was
   already correct. The real defects (name-based simulator selection, ssh arg
   splitting) are fixed and verified as of 2026-07-31, so `ios build` is now a
   trustworthy signal — but it was never the blocker I described.
1. **Wire the tests up (D-8).** Nothing else is measurable until `xcodebuild test`
   runs. First run establishes the real baseline — I expect failures.
2. **`FakeTransport` behind the `MeshTransport` protocol (D-9).** This is what
   makes mesh failures reproducible on demand instead of by luck. Scenarios it
   must drive deterministically:
   - simultaneous mutual invitation (**D-7**'s acceptance test)
   - rapid join/leave flapping at configurable rates
   - reconnect with a stale/changed `MCPeerID`
   - a peer that goes silent without disconnecting (ghost detection)
   - packet loss, duplication, reordering, TTL exhaustion
   - malformed control packets for every magic prefix, `KRO!` included
3. **Thread Sanitizer.** Add a TSan test configuration. **A TSan-clean run over
   the flap harness is the acceptance criterion for D-4, D-6, and D-7.** This is
   the only way to prove the isolation work actually landed rather than moved.
4. **The escape-hatch counter as a regression gate.** `@unchecked Sendable` (5),
   `nonisolated(unsafe)` (14), and `MainActor.assumeIsolated` (5) are a direct
   measure of how much of the concurrency model is unchecked. Each P0/P1 item
   should *lower* these counts; a CI check that they never increase prevents
   silent regression. **D-4 is only done when `AudioEngine` compiles without
   `@unchecked Sendable`. D-7 is only done when `MultipeerTransport` does.**
5. **Two-device manual checks**, named explicitly per item and reported as manual
   and unverified until actually run. Minimum set: background→foreground→PTT
   (**D-1**); simultaneous press by both devices (**D-3**); 10-minute continuous
   transmission (**D-4**); walk-out-of-range-and-back ×5 (**D-7**); AirPods
   connect/disconnect mid-transmission (**D-5**); phone call mid-transmission (**D-5**).
6. **Capture crash logs from now on.** There is currently no ingestion path at
   all. Before further device testing, pull `.ips` files off the phone after each
   session and keep them with the `dSYM` in `build/`. Without this, the next round
   of this audit will be as evidence-starved as this one.

Per-item reporting will state what was built, what was run, and **specifically
what was not verified**.

---

## F. Open questions

1. **Background mesh: is it a real product requirement?** The inaudible-tone
   keep-alive is the highest App Store rejection risk in the project (§2.5.4).
   The legitimate path is PushToTalk.framework, which is a meaningful rewrite of
   the PTT layer and requires an entitlement. The alternatives are: (a) adopt
   PushToTalk.framework properly; (b) drop background operation and say so in the
   UI; (c) ship as-is and gamble on review. This decision gates **D-13** and
   changes the shape of **D-3**. Which way?

2. **Wi-Fi Aware: keep or cut for v1?** It is entitled, shipped, and
   **non-functional** — the required `WiFiAwareServices` Info.plist key is missing,
   so it logs an error and dies at startup. It is also untestable (needs iOS 26 +
   paired devices, per `ROADMAP.md`). Restoring it properly is real work; cutting
   it for v1 removes an entire transport's worth of defects from the peer-identity
   work in **D-6**. Cut, or fix?

3. **Feature surface.** 40 services, 22 k lines of views, and ~15 headline
   features (Swarm, Chorus, CICADA, Darkroom, DeadDrop, Witness, Babel,
   Lighthouse, UWB positioning, offline maps, Protect suite…) — none of which are
   the walkie-talkie. Several are unbounded-memory sites. Is deferring some of
   them from v1 on the table? This does not change the P0 work, but it
   substantially changes **D-6**, **D-10**, and the App Store surface.

4. **Live Activities.** Disabled since March because the extension crashed the
   host app, but `NSSupportsLiveActivities: true` and the extension still ships.
   Fix and enable, or remove entirely?

5. **Is there any device crash you can reproduce on demand right now?** This is
   the highest-value thing you could give me. I have no crash logs at all, so
   every crash row in section B is source-derived. One reproducible case would
   let me confirm or kill several hypotheses at once. Even a rough "it dies when
   I do X" is worth a lot.

6. **Can I get crash logs off the test device?** Settings → Privacy & Security →
   Analytics & Improvements → Analytics Data, filter for `Chirp`, share them out.
   Or connect the phone and use Xcode → Window → Devices and Simulators → View
   Device Logs. Either would move most of section B from Likely to Confirmed.

7. **How many physical devices are available for testing?** Several defects
   (mutual-invite storm, mesh forwarding, floor collisions) only manifest with 3+
   peers. Two devices will not reproduce them.

8. **Test baseline expectations.** The suite has never run in CI. When I wire it
   up (**D-8**) I expect some failures. Do you want me to fix failing tests as
   part of D-8, or catalogue them and proceed with the P0 crash work first?

---

## Summary

The recurring pattern across every subsystem is the same: **an invariant is
asserted in a comment and enforced nowhere.** `MultipeerTransport`'s doc-comment
claims its mutable state is main-confined (it isn't, and the comment names a field
that doesn't exist). `AudioEngine`'s `nonisolated(unsafe)` comment defends an
isolation property when the actual hazard is buffer lifetime. `AudioSessionManager`
is named as if it owns the audio session but owns nothing.

Swift 6 strict concurrency is **already fully enabled** — the compiler has been
trying to report all of this. The 24 escape hatches are the record of it being
told to stop. The remediation is therefore unusually well-defined: **earn the
removal of each hatch.** When `AudioEngine` and `MultipeerTransport` compile
without `@unchecked Sendable`, the isolation defects in this audit are
structurally gone rather than moved — which is precisely the difference between
the fix and the band-aid.

The two cheapest high-value items are **D-8** (wire the tests into a scheme —
roughly a 6-line change that unlocks 423 existing tests) and **D-1** (give the
audio session an owner — which likely restores basic PTT function after
backgrounding). I recommend starting there.
