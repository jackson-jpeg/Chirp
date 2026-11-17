# ChirpChirps 1.0: code audit for the 2.0 rewrite (code-reading half)

Read-only audit of `Chirp/Sources` (about 26,900 lines of Swift, 97 files) and `ChirpTests`
(about 7,900 lines) at master `1d9dc53`, 2026-11-17. Nothing was built or run. Every claim
below is either "the code shows" (cited file:line, paths relative to `Chirp/Sources/` unless
they start with `ChirpTests/` or are top-level) or a claim the hardware half must test
(section 8).

## Summary

The core that 2.0 needs (Opus capture and playback, a pure floor-control reducer, a
MultipeerConnectivity transport with a single send gate, a mesh packet with dedup, replay
window and TTL, and a Demo Mode sandboxed at that gate) is real code on a real data path,
and it is the only part worth carrying over, rewritten clean. Around it sits a large layer
that changes nothing or shows numbers it does not have: "mesh intelligence" and pheromone
routing are never consulted by the router, cover traffic is invisible to the filter meant to
discard it, the hop count and range on the home screen are computed from the TTL and read
"2 hops" between two phones side by side, signal bars are a constant 3, key "rotation" gives
no forward secrecy, live captions can never be authorized, and the Voice Messages inbox is
filled only by Demo Mode and screenshot seeding. Two defects matter for the three proofs:
push-to-talk audio and floor control carry no channel ID, so channels do not separate voice
(and locked channels do not protect it), and the receive jitter buffer is never reset for a
new speaker, so a sender whose sequence counter restarts (relaunch, or a third device) can be
silently dropped. The 2.5.4 rejection is structural: the audio session and an engine with
its input node are started at launch and never stopped. Identity is split three ways
(MultipeerConnectivity display name, routing UUID, key fingerprint), which is why friends,
the nearby list and blocking disagree with each other. Verdict: carry over the audio,
floor, packet/router, transport gate, identity keys, block and consent designs, each
rewritten with one identity model; drop everything else.

| Subsystem | Main files | Verdict |
|---|---|---|
| Audio capture, Opus, playback | `Services/Audio/AudioEngine.swift`, `OpusCodec.swift`, `JitterBuffer.swift` | CARRY OVER (rewrite clean) |
| Audio session lifecycle | `Services/Audio/AudioSessionManager.swift`, `App/ChirpApp.swift` | REWRITE FROM SCRATCH |
| Floor control | `Services/PTT/FloorMachine.swift`, `FloorSession.swift` | CARRY OVER (rewrite clean) |
| PTT glue | `Services/PTT/PTTEngine.swift` | REWRITE FROM SCRATCH |
| Transport | `Services/Network/MultipeerTransport.swift` | CARRY OVER (rewrite clean) |
| Mesh packet and router | `Models/MeshPacket.swift`, `Services/Network/MeshRouter.swift` | CARRY OVER (rewrite clean) |
| Packet dispatch | `Services/Network/MeshDelivery.swift` | REWRITE FROM SCRATCH |
| Texts and delivery ticks | `Services/TextMessageService.swift`, `Models/MeshTextMessage.swift`, `Services/Persistence/*` | REWRITE FROM SCRATCH |
| Channels and invite codes | `Services/PTT/ChannelManager.swift`, `Services/Security/ChannelCrypto.swift`, `ChannelKeyStore.swift` | CARRY OVER invite code and key derivation; DROP epoch rotation |
| Who is nearby | `MeshBeacon.swift`, `Network/PeerTracker.swift`, transport `peers`, channel rosters | REWRITE FROM SCRATCH (one source) |
| Identity keys | `Services/Security/PeerIdentity.swift` | CARRY OVER (rewrite clean) |
| Blocking and reporting | `Services/Moderation/BlockList.swift`, `ReportService.swift`, `Views/Components/PeerActionSheet.swift` | CARRY OVER (rewrite clean) |
| Incoming text filter | `Services/Moderation/TextFilter.swift` | CARRY OVER (small, optional) |
| Location check-in and consent | `Services/LocationSharing.swift`, `LocationService.swift`, `Views/LocationConsentSheet.swift` | CARRY OVER (rewrite clean); DROP the chat location attachment |
| Demo Mode | `Services/Demo/DemoMode.swift`, `DemoContent.swift` | CARRY OVER (rewrite clean) |
| Friends | `Services/FriendsManager.swift`, `Views/AddFriendView.swift` | REWRITE FROM SCRATCH |
| Mesh intelligence, pheromone routing | `Network/MeshIntelligence.swift`, `PheromoneRouter.swift`, `Models/DeliveryACK.swift` | DROP |
| Cover traffic | `Services/Security/MeshShield.swift` | DROP |
| Store-and-forward | `Services/StoreAndForwardRelay.swift` | DROP (2.0) |
| Live transcription | `Services/LiveTranscription.swift`, `Views/TranscriptOverlayView.swift` | DROP |
| Voice Messages inbox | `Services/VoiceMessageQueue.swift`, `Audio/VoiceClipPlayer.swift`, `Views/VoiceMessagesView.swift` | DROP |
| Chat voice notes | `Utilities/VoiceNoteRecorder.swift`, `Views/Components/VoiceNoteBubbleView.swift` | DROP |
| Images, files | `FileTransferService.swift`, `ImageCompressor.swift`, picker and preview views | DROP |
| Map and offline maps | `Views/GeoMapView.swift`, `OfflineMapManager.swift` (MapLibre) | DROP |
| Proximity alerts, quick replies, reactions, typing, read receipts | `ProximityAlert.swift`, `QuickReply.swift`, parts of `TextMessageService.swift` | DROP |
| Diagnostics, telemetry, screenshot seed | `Views/DiagnosticsView.swift`, `Components/DebugOverlayView.swift`, `Audio/AudioTelemetry.swift`, `App/ScreenshotSeed.swift` | DROP (keep the telemetry idea for the device harness) |
| All views | `Views/*` | DROP (new design) |
| Build config | `project.yml` | REWRITE (no `UIBackgroundModes`) |

## 1. Method and limits

Read: `ViewModels/AppState.swift` in full (it constructs and wires everything), every file
on the audio, floor, transport, router and text paths in full, and every other service by
outline plus caller search (`grep` for each property and function outside its own file).
"Dead" below means no caller outside its own file, tests, Demo Mode or `ScreenshotSeed`.
The code cannot show: whether audio is audible, latency, radio range, iOS permission prompt
timing, background behavior, the microphone indicator, or how MultipeerConnectivity behaves
with more than two devices. Those are section 8.

## 2. The three proofs, as far as the code goes

**Push to talk, both ways.** The path is complete. Press: `FloorMachine.swift:186-196`
(idle to holding, open microphone, broadcast `floorRequest`) to `PTTEngine.swift:105-110`
to `AudioEngine.startCapture` (`AudioEngine.swift:149-199`: tap with `format: nil`, copy out
of the render thread, resample to 16 kHz Int16, 20 ms Opus frames at 24 kbps,
`Models/Constants.swift:8-12`). Each frame goes `PTTEngine.swift:62-83` to
`MultipeerTransport.sendAudio` (`MultipeerTransport.swift:207-233`, unreliable mode). Receive:
`MultipeerTransport.swift:500-531` to `MeshRouter.handleIncoming` to
`MeshDelivery.swift:105-115` to `AudioEngine.receiveAudioPacket` (decode, jitter buffer,
20 ms drain timer, `AudioEngine.swift:226-360`). Code-level defects that hardware must check:

- Audio and floor messages are sent with `channelID: nil` (`PTTEngine.swift:79`, `:91`, heartbeat
  `:218`). The channel filter only drops packets whose channel ID is non-empty and different
  (`MeshDelivery.swift:87-96`), so every connected device plays every transmission, whatever
  channel either side has open, and one person talking blocks the button for everyone in
  range. Locked channels encrypt text only; voice relies on MultipeerConnectivity's link
  encryption (`MultipeerTransport.swift:112-116`), which every connected device shares.
- The jitter buffer drops any frame whose sequence number is not after the last one played
  (`Audio/JitterBuffer.swift:53`). It is reset only when this device opens its own microphone
  (`PTTEngine.swift:107`), never when a new speaker starts. Sequence numbers are per sender and
  restart at 0 on launch (`PTTEngine.swift:35`, `:228-232`). A listener that last played
  sender X up to frame N drops every frame below N from any later speaker whose counter is
  lower, until that listener next talks.
- The floor is one global state with no listening timeout (`FloorMachine.swift:259-269`,
  `:326-333`). A lost `floorRelease` (relayed control packets go unreliable,
  `MultipeerTransport.swift:311-313`) leaves listeners "receiving" until ghost pruning, which
  is keyed to heartbeats that keep coming (`Network/PeerTracker.swift:84-92`), so possibly
  until the speaker's 120 s watchdog (`PTTEngine.swift:198-206`).
- `floorGranted` is sent and documented as ignored (`FloorMachine.swift:271-283`): dead wire traffic.

**Texts with delivery acks.** Real and tested in-process
(`ChirpTests/LoopbackHarnessTests.swift:367`). Send: `TextMessageService.swift:146-198` to
`MeshDelivery.makeTextSendHandler` (`MeshDelivery.swift:37-70`). Receive:
`TextMessageService.swift:456-535` stores, dedups by message ID, and replies `ACK!` + UUID
(`:540-555`); the sender flips `.sent` to `.delivered` (`:559-587`). Limits the code shows:

- The tick means "some device stored it", not "a channel member got it". Any device in range
  stores and acks a message on any open channel it receives; nothing checks membership
  (`TextMessageService.swift:497-529`).
- Ticks live in memory only. `MessageRecord` has no status column
  (`Services/Persistence/MessageRecord.swift:9-17`) and new messages default to `.sent`
  (`Models/MeshTextMessage.swift:31`), so every tick reverts after a relaunch.
- Every received text produces two acks: the text ack and a pheromone `DeliveryACK`
  broadcast (`MeshDelivery.swift:140-145`), which each receiver re-broadcasts as a new packet
  (`Network/PheromoneRouter.swift:114-122`). Both use the magic `ACK!`, disambiguated by trying
  to parse JSON first (`MeshDelivery.swift:154-163`); the comment there records that this once
  left every message stuck at `.sent`.

**A relay hop.** The mechanism exists: `MeshRouter.swift:201-206` forwards any accepted packet
with TTL above 1 to every connected peer except the one it came from
(`MultipeerTransport.swift:304-318`). TTLs are fixed by priority (`Models/MeshPacket.swift:63-70`):
audio 2 (one relay at most), beacons and acks 4, texts 6. The code cannot show that a hop ever
happens: MultipeerConnectivity auto-invites and auto-accepts every peer it sees
(`MultipeerTransport.swift:541-558`), so any two devices that can relay through a third usually
also connect directly. No test covers a line topology: the harness links every node to every
other (`ChirpTests/LoopbackHarnessTests.swift:24-29`). Relayed control packets switch from
reliable to unreliable delivery (`MultipeerTransport.swift:311-313`), so a relayed text has no
retransmission and its ack may never return.

## 3. Dead code (constructed or written, never used for anything the user sees)

- `MeshIntelligence`: constructed `AppState.swift:202`, fed topology and pheromones
  (`AppState.swift:551-571`, `:594-602`), never read by routing. `shouldRelay`,
  `selectRelayPeers`, `bestPath`, `meshHealthScore`, `reachableNodeCount`, `recordReceive`,
  `recordLoss`, `extraTTLReduction` have no production caller (only
  `PheromoneRouter.swift:139` wraps one, itself uncalled). `MeshRouter` never references it.
- `PheromoneRouter`: its only effects are extra `ACK!` broadcasts and trail summaries added to
  beacons (`MeshBeacon.swift:734-739`). `isSporeMode` is computed and read by nothing.
- `AudioEngine.setTargetBitrate` (`AudioEngine.swift:390`): no caller. Adaptive bitrate is dead.
  `onRawAudioBuffer` (`:16`): no subscriber.
- `MultipeerTransport.sendRawWireData` (`:238`) and `onReconnectFailed` (`:80`): no caller or subscriber.
- `LiveTranscription.requestAuthorization()` (`LiveTranscription.swift:91`) is never called,
  and `startTranscribing` returns unless already authorized (`:112`). Nothing else in the app
  asks for speech permission, so captions can never run, yet `project.yml:93` declares
  `NSSpeechRecognitionUsageDescription` and `AppState.swift:409-425` routes all decoded audio to it.
- `VoiceMessageQueue.queueMessage`, `attemptDelivery`, `receiveMessage`: called only from
  `App/ScreenshotSeed.swift:175-199` (and Demo overlay). No production path records into, sends
  from or receives into the Voice Messages inbox that the home toolbar always links to
  (`Views/HomeView.swift:1091-1099`).
- `ChannelManager.kickPeer` (`Services/PTT/ChannelManager.swift:313`): no caller, and it would only edit the local roster.
- `DebugOverlayView`: referenced nowhere.
- `Services/PTT/PTTEngine.swift:36` `stateObservationTask`: never assigned.

## 4. Faked (UI state not backed by the data it claims)

- **Hop count.** `MeshRouter.swift:210-216` computes hops as `maxTTL (8) - ttl`, but packets
  start at 2, 4 or 6, not 8. A heartbeat received directly reads as 2 hops, a beacon as 4.
  The home strip shows "N hops" and turns green at 3 (`Views/HomeView.swift:822-834`), Settings
  shows Max Hops (`Views/SettingsView.swift:298`).
- **Range.** `estimatedRangeMeters = maxHops * 80` (`MeshRouter.swift:276`), shown in release in
  Settings (`Views/SettingsView.swift:312`) and Diagnostics (`Views/DiagnosticsView.swift:97`).
- **Relay active.** `packetsRelayed` increments before the transport finds any target
  (`MeshRouter.swift:202-204` vs `MultipeerTransport.swift:305-306`), so `relayed > 0`
  (`Views/HomeView.swift:837-840`) is true as soon as two phones exchange a heartbeat.
- **Beacon hops.** Beacons are sent with `hopCount: 0` (`MeshBeacon.swift:752`) and nothing
  increments it on relay, so every node is "direct" (`MeshBeacon.swift:213-215`).
- **Signal strength.** Every MultipeerConnectivity peer gets `signalStrength: 3`
  (`MultipeerTransport.swift:364`), PeerTracker uses 2 (`PeerTracker.swift:33`). Signal bars
  (`Views/HomeView.swift:758`, `Views/DiagnosticsView.swift:155`) and proximity alert distance
  words (`Services/ProximityAlert.swift:85`, `:129-133`) come from these constants.
- **Readiness rows.** "Peer-to-peer Wi-Fi" and "Encrypted channels" are hard-coded
  `ready: true` (`Views/HomeView.swift:380`, `:382`).
- **Key rotation.** `ChannelCrypto.epochKey` (`Services/Security/ChannelCrypto.swift:108-121`)
  claims forward secrecy, but every epoch key is HKDF of the same base key, so anyone with the
  channel key derives every epoch. `KRO!` rotation packets (`AppState.swift:348-354`,
  `MeshDelivery.swift:182-185`) are plaintext and unauthenticated.
- **Cover traffic.** `MeshShield` encrypts its `DEADBEEF` marker (`MeshShield.swift:125-132`)
  but receivers check the marker on the raw, still-encrypted payload (`MeshDelivery.swift:100`),
  so the check never matches; control cover packets run through text and file decryption and
  are discarded as unparseable. It runs whenever the active channel is locked, with a random
  origin ID per packet (`MeshShield.swift:138-149`). `FEATURE-INVENTORY.md:60` calls it an option;
  there is no toggle.
- **"No internet required" with a map.** The map style and tiles load from
  `https://tiles.openfreemap.org` (`Services/OfflineMapManager.swift:35`, `Views/GeoMapView.swift:100`).
- **"Voice messages delivered over the mesh"** (`FEATURE-INVENTORY.md:43-46`): see section 3.

## 5. Duplicated

- **Who is nearby: four sources.** Transport `peers` keyed by display name
  (`MultipeerTransport.swift:359-366`), `PeerTracker` keyed by routing UUID from heartbeats, which
  HomeView polls into its own separate count (`Views/HomeView.swift:1162-1166`), `MeshBeacon.knownNodes`
  keyed by routing UUID, and per-channel rosters (`AppState.swift:682-684`).
- **Three identities for one person.** Display name (`MCPeerID`, `MultipeerTransport.swift:105`),
  routing UUID (`AppState.swift:145-153`), key fingerprint (`PeerIdentity`). Consequences:
  a friend added by code is keyed by fingerprint (`Views/AddFriendView.swift:337-340`) but
  online status compares against display names (`AppState.swift:687-693`), so that friend never
  shows online; the nearby bubbles (`Views/HomeView.swift:1238-1240`) are display-name peers
  and are not filtered by the UUID-keyed block list (only map pins are, `:1250`, `:1276`);
  the router ignores any block ID that is not a UUID (`MeshRouter.swift:89-91`). Callsigns
  are 20 words by 99 numbers (`Utilities/CallsignGenerator.swift`), and a rename does not reach
  the transport, floor or sent messages until relaunch (`AppState.swift:59-61`, `:165`, `:244`).
- **Three voice paths, three players.** Live PTT (Opus, `AVAudioPlayerNode` in `AudioEngine`);
  chat voice notes (AAC via `AVAudioRecorder`, base64 inside a text message,
  `Views/ChannelView.swift:432-439`, played by `AVAudioPlayer` in
  `Views/Components/VoiceNoteBubbleView.swift:112`); Voice Messages inbox (Opus files,
  `VoiceClipPlayer` through `AudioEngine`, demo-only).
- **Two acks** with one magic (section 2). **Two location paths**: sealed per-recipient beacon
  positions (`MeshBeacon.swift:486-509`) and a plaintext coordinate text message flooded at TTL 6
  (`Views/ChannelView.swift:1198-1209`, consent-gated at `:1179-1193`). **Two image/file paths**:
  base64 images inside text up to 100,000 characters (`Models/MeshTextMessage.swift:79`) and
  chunked `FileTransferService`.
- **Two "store for offline peers" queues**: `StoreAndForwardRelay` (texts) and `VoiceMessageQueue`.

## 6. App Review findings in the code

- **2.5.4.** `AudioEngine.setup` activates a `.playAndRecord` session and starts an engine with
  its input node at launch (`AudioEngine.swift:86-127`, `AudioSessionManager.swift:25-45`), called
  from `AppState.start` (`AppState.swift:495`). Nothing reacts to backgrounding
  (`App/ChirpApp.swift:26-36`); teardown happens only in `AppState.stop`, which nothing calls.
  With `UIBackgroundModes: audio` (`project.yml:104-105`) the app can stay alive indefinitely.
  The 20 ms playback timer, once started, runs until this device next talks
  (`AudioEngine.swift:221-224`, `:242-244`). A worked fix on 1.0 is on branch
  `fix/2-5-4-foreground-only` (commit `0fce281`); 2.0 should open the session on press or on
  incoming floor and close it when idle.
- **5.1.1(iv) prompts.** `AppState.start` runs from the root `.task` whether or not onboarding
  is complete (`App/ChirpApp.swift:10-21`) and starts advertising and browsing
  (`AppState.swift:508`), which is what triggers the Local Network prompt, and the engine with
  the input node (see above). Microphone permission itself is asked only on demand
  (`AppState.swift:89-101`, `:480-482`). Notifications are asked at launch once onboarding is
  done (`AppState.swift:546-548`), with no user action.
- **5.1.2(i).** Location is in good shape: no "Always" string (`project.yml:94-98`), check-ins are
  memory-only, 15 minutes, never resumed (`Services/LocationSharing.swift:11-26`, `:85`, `:254`), and
  the beacon can only get a coordinate through that gate (`AppState.swift:327-332`). Blocking is
  keyed to the signed identity and follows a reinstall (`MeshBeacon.swift:439-484`,
  `AppState.swift:305-316`). The gaps are the nearby list and peer count (section 5).
- **2.1(a).** Demo Mode is isolated below every service: one send gate drops everything while
  sandboxed and anything addressed to a `demo-` channel (`MultipeerTransport.swift:333-350`),
  inbound is ignored (`:503`), and simulated packets enter through the real receive path
  (`AppState.swift:466-468`). Blocked demo peers are filtered (`AppState.swift:318-325`).

## 7. Per-subsystem verdicts (reasons beyond the sections above)

- **Audio core: CARRY OVER (rewrite clean).** Worth keeping: the render-thread copy
  (`AudioEngine.swift:171-193`, `:444-500`), the persistent converter fed `.noDataNow`
  (`:615-629`, which fixed "first 100 ms then silence"), the test seam that drives the real
  encode path without hardware (`:403-426`), and the DEBUG sine-mic flag for the simulator
  (`:44-56`). Change: per-speaker jitter state reset on floor change, stop the drain timer when
  idle, no session at launch. Only hardware can show it is audible and clean.
- **Audio session: REWRITE FROM SCRATCH.** Its whole shape (configure once at launch, never
  release) is the 2.5.4 cause. Interruption and route-change handling (`:84-164`) is a good
  checklist to reimplement.
- **Floor: CARRY OVER (rewrite clean).** A pure reducer with effects is the right design and is
  the best-tested code here (`ChirpTests/FloorMachineTests.swift`, `FloorMeshTests.swift`,
  `FloorControlTests.swift`, `FloorHolderTests.swift`). Change: scope to a channel, add a
  listening timeout, drop `floorGranted`, keep the sender-impersonation check (`FloorMachine.swift:244-249`).
- **PTT glue: REWRITE.** It is wiring plus a watchdog; the new session lifecycle replaces it.
- **Transport: CARRY OVER (rewrite clean).** Keep the single `emit` gate, the `MeshRadio` seam,
  fresh advertiser and browser per restart (`:166-193`, which records a crash it fixed) and
  captured send targets. Change: peer identity must not be the display name; add an invitation
  tie-break (both sides currently invite each other, `:554-558`); pull-to-refresh disconnects
  everyone (`Views/HomeView.swift:1755-1759`). A session holds at most 8 peers (platform limit).
- **Packet and router: CARRY OVER (rewrite clean).** Dedup, per-origin-and-type replay window and
  sender-stamped sequence numbers are sound and covered by
  `ChirpTests/MeshSequenceRegressionTests.swift`. Drop the inferred priority, fake stats and
  magic-string sniffing; give the payload an explicit type byte.
- **Dispatch: REWRITE.** `MeshDelivery` routes by the first four ASCII bytes, falls through to
  "try to decrypt as text, then as file" for everything unknown (`:202-220`), and owns ack side effects.
- **Texts: REWRITE FROM SCRATCH.** Keep the idea (message ID, dedup, ack by ID, GRDB history with
  file protection, `Services/Persistence/MessageDatabase.swift:56-64`). Persist tick state, ack only
  from channel members, drop reactions, typing, read receipts, threads, attachments.
- **Channels: CARRY OVER invite code only.** `ChannelCrypto.swift:21-92` (HKDF from a seed bound to
  the channel ID, round-trips, tested in `ChirpTests/ChannelInviteTests.swift`). DROP epochs and `KRO!`.
- **Who is nearby: REWRITE.** One roster keyed by one identity, fed by the transport and a
  signed presence beacon. Note the beacon broadcasts battery level to strangers (`MeshBeacon.swift:726`).
- **Identity keys, blocking, reporting, consent, Demo Mode: CARRY OVER (rewrite clean)** for the
  reasons in section 6. Report is a local log plus a `mailto:` (`Moderation/ReportService.swift:5-11`).
- **Everything marked DROP in the table:** outside 2.0 scope, and sections 3 to 5 show each is
  dead, faked or a duplicate.

## 7a. What the tests prove, and what they mock away

30 test files, 370 test functions. Strong: the floor reducer, wire formats and fuzzing
(`DeserializationFuzzTests`, `WireFormatAlignmentTests`), router sequence handling, the text
send policy (`TextSendPolicyTests` runs the production `makeTextSendHandler`), Demo isolation
at the real transport with a spy radio (`DemoTransportIsolationTests`), location gating
(`LocationCheckInTests`, `PositionPrivacyTests`). `LoopbackHarnessTests` runs real routers,
delivery, codec and jitter buffer between in-memory nodes, including a sine tone end to end
(`:283`). What they cannot prove: the microphone, the speaker, `AVAudioSession` (lifecycle tests
post fake notifications, `AudioSessionLifecycleTests.swift:104-204`), MultipeerConnectivity
(replaced by `InMemoryTransport`, full mesh only), a relay through a node that is not directly
linked, channel scoping of audio (no test sends audio on two channels), a second speaker after
the first (no test of jitter state across speakers), and the UI. `MeshIntelligenceTests` and
`PheromoneRoutingTests` test code that production never consults.

## 7b. Older documents checked against the code

`FEATURE-INVENTORY.md` is wrong on: live transcription (cannot run), voice messages delivered
over the mesh (inbox has no production sender), "offline-capable map" (online tiles), cover
traffic "option" (always on for locked channels, no toggle), and routing intelligence
(computed, never used). Its "multi-hop audio relay" is at most one relay (TTL 2).
`ARCHITECTURE_AUDIT.md` (2026-07-31, described 44,100 lines; now about 26,900) lists crash
classes B-1 to B-9; its B-3, B-4, B-5, B-7 and B-9 fixes are visible in the code
(`AudioEngine.swift:171-193`, `:37-41`; `MultipeerTransport.swift:26-32`;
`AudioSessionManager.swift:93-98`; `MultipeerTransport.swift:484-490`). It had no crash logs; its
B-1 (PTT dead after background and foreground) is not addressed by any lifecycle code and needs H13.

## 8. Claims the hardware half must prove or disprove

Setup: one iPhone and one simulator, Debug build, both on the same Wi-Fi. Run the simulator
with `-ChirpSineMic YES` so its "microphone" is a pulsed 440 Hz tone (`AudioEngine.swift:44-56`).
Fresh install unless stated. "Phone" is A, "simulator" is B. Each line: do, then observe, then
what the code predicts.

1. **H1 Microphone at launch.** Fresh install, open the app, stay on the first onboarding page.
   Observe the orange microphone indicator and Control Center's "in use" entry. Predicts: the
   input is live before any press (`AudioEngine.swift:117-120`).
2. **H2 Prompt timing.** Same run. Note which system prompts appear and on which screen
   (Local Network, microphone, notifications). Predicts: Local Network during onboarding,
   before any explanation or tap (`AppState.swift:508`).
3. **H3 Talk A to B.** Both on General. Hold on A for 5 s while speaking. Observe B shows A as
   speaker and plays audible, intelligible audio; estimate latency with a clap. Predicts: works.
4. **H4 Talk B to A.** Hold on B for 5 s (sine tone). Observe A plays a pulsed tone. Predicts: works.
5. **H5 Restarted sender.** A talks 30 s to B. Force-quit A, relaunch, talk 10 s. Observe
   whether B plays it. Predicts: B drops A's audio (sequence restart vs stale jitter state,
   `JitterBuffer.swift:53`), unless B talked in between.
6. **H6 Channels do not separate voice.** Create channel "X" on A and open it; B stays on General.
   A talks. Observe whether B plays it and whether B's talk button is refused meanwhile.
   Predicts: B hears A and is blocked (`PTTEngine.swift:79`, `:91`).
7. **H7 Locked channel voice.** A creates a locked channel, does not share the code, talks.
   Observe whether B (no code, on General) hears it. Predicts: yes.
8. **H8 Delivery tick.** A sends a text on General. Observe A's tick going from sent to
   delivered, and the time it takes. Relaunch A. Predicts: delivered, then back to sent after relaunch.
9. **H9 Tick from a non-member.** A creates open channel "Y" and sends a text there; B never
   joins "Y". Observe A's tick and whether "Y" or its message appears anywhere on B.
   Predicts: A shows delivered, acked by B.
10. **H10 Relay hop.** Needs a third device. Place A and C out of each other's range with B
    between (or prove they cannot connect directly). Send a text and a 5 s talk from A.
    Observe arrival at C and B's Diagnostics "relayed" count. Predicts: possible in code (text
    TTL 6, audio TTL 2), unproven, relayed text sent unreliable. With only phone and simulator
    this claim cannot be tested: record it as unproven, not as passed.
11. **H11 Fake hops and range.** A and B side by side, connected. Observe the home mesh strip,
    Settings Max Hops and Est. Range. Predicts: 2 to 4 hops, 160 to 320 m, "relay" shown, with
    no relay possible.
12. **H12 Constant signal.** Walk A away from the Mac until it disconnects. Observe signal bars
    in Diagnostics. Predicts: 3 of 3 until the peer vanishes.
13. **H13 Background.** Connected, send A to the home screen for 5 minutes, then B talks.
    Observe whether A plays it, whether the peer stays connected, and whether talking works
    after returning (old B-1). Repeat on the `fix/2-5-4-foreground-only` build. Predicts: 1.0
    keeps playing in background; the fix branch does not.
14. **H14 Collision.** Press on A and B within about 100 ms. Observe that exactly one transmits,
    the other shows refused, and its microphone indicator goes off. Predicts: works (`FloorMachine.swift:302-324`).
15. **H15 Lost speaker.** While A transmits, turn on Airplane Mode on A. Observe how long B shows
    A as speaking and whether B can then talk. Predicts: up to 45 s (ghost threshold) or longer.
16. **H16 Interruption.** While A transmits, trigger Siri or an incoming call on A. Observe the
    floor released on both, and PTT working after. Predicts: released; recovery depends on `shouldResume`.
17. **H17 Bluetooth input lost.** Transmit through a Bluetooth headset, switch it off. Observe
    transmission stops on both sides. Predicts: stops (`AudioSessionManager.swift:156-163`).
18. **H18 Block.** On A, block B from the peer sheet. Observe: B's texts hidden, B's talk not
    played on A, and whether B still appears in A's nearby bubbles and peer count. Predicts:
    hidden and silent, but B still listed and counted (`Views/HomeView.swift:1238-1240`).
19. **H19 Block survives reinstall.** Delete and reinstall on B (new callsign), reconnect.
    Observe A still blocks B. Predicts: held, if B's Keychain identity survives reinstall.
20. **H20 Rename.** Change A's callsign in Settings, do not relaunch. Observe the name on B for
    a new text, a talk and the nearby list. Predicts: old name until A relaunches.
21. **H21 Captions.** Receive a transmission with captions visible. Predicts: never any
    caption and never a speech permission prompt.
22. **H22 Voice Messages screen.** After H3 to H9, open the waveform toolbar button.
    Predicts: empty outside Demo Mode.
23. **H23 Demo isolation.** Turn Demo Mode on A with B nearby. Observe B loses A within
    seconds and never shows demo peers or messages; turn it off and observe rediscovery time.
    Predicts: isolated (`MultipeerTransport.swift:127-140`).
24. **H24 Location consent.** Check in on A twice in a row (let the first expire or stop it).
    Observe the consent sheet both times, B's map pin only during the check-in, and the pin
    disappearing after. Then put A offline from the internet but on the same LAN and open the
    map. Predicts: consent each time; map tiles blank without internet.
25. **H25 Two-device connect.** Fresh launch on both. Time to connect and whether the
    connection flaps (both sides invite each other). Check the device log for repeated
    "connecting"/"disconnected" lines from category `Multipeer`.

Hardware claims listed: 25 (H1 to H25). H10 needs a third device.
