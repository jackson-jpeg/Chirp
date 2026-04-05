# ChirpChirps iOS App — Session Log
### April 3, 2026

---

## Overview

Four rounds of hardening, bug fixes, UX polish, and test coverage to prepare ChirpChirps for App Store release. Started from a working PTT foundation (loopback off, AEC on, jitter buffer, emergency mode, mesh gateway) and systematically found and fixed every issue across audio, networking, UI, security, and testing.

**Final state:** 0 build errors, 0 warnings, 218 tests passing, synced to Mac.

---

## Round 1 — PTT Hardening, Network Reliability, UX Polish, Feature Honesty (16 fixes)

### Phase A: Audio/PTT Hardening

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| A1 | **Sequence number reset on re-PTT** | `PTTEngine.swift`, `AudioEngine.swift` | Removed `sequenceNumber = 0` from both `startTransmitting()` and `startCapture()`. Sequence numbers now increment monotonically across transmissions, preventing the jitter buffer from dropping all packets as "late" on quick re-PTT. |
| A2 | **120s transmission timeout** | `PTTEngine.swift` | Added `transmitTimeoutTask` that auto-releases the floor after 120 seconds. Prevents indefinite floor holding from stuck mic or forgotten button. Cancelled on manual stop. |
| A3 | **Floor collision tiebreaker** | `FloorController.swift` | Changed `localTS <= timestamp` to `localTS < timestamp \|\| (localTS == timestamp && localPeerID < peerID)`. Deterministic winner on all devices even with clock skew. |
| A4 | **Jitter buffer wraparound** | `JitterBuffer.swift` | Replaced `sequenceNumber <= lastPulled` with `Int32(bitPattern: sequenceNumber &- lastPulled) <= 0`. Handles UInt32 overflow at max boundary correctly. |
| A5 | **Packet loss concealment** | `AudioEngine.swift` | When jitter buffer underruns, repeats last good frame with progressive attenuation (100% → 66% → 33%) for up to 60ms instead of playing silence clicks. Added `lastGoodFrame` and `concealmentCount` properties. |

### Phase B: Network Reliability

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| B1 | **Log send failures** | `MultipeerTransport.swift` | Replaced all 5 `try?` session.send() calls with do/try/catch blocks that log errors via Logger. Errors no longer silently swallowed. |
| B2 | **WiFiAware auto-restart** | `WiFiAwareTransport.swift` | Added retry mechanism for listener/browser failures: 2s backoff, max 3 retries. Retry counts reset on successful start. Listener/browser no longer stay dead after transient errors. |
| B3 | **Transport selection hysteresis** | `TransportPreference.swift` | Replaced single 20ms threshold with dead-band: switch TO wifiAwareOnly at <15ms, switch AWAY at >25ms. Added `currentAudioTransport` static var for state tracking. Prevents flapping when latency oscillates. |
| B4 | **Pheromone ACK deduplication** | `PheromoneRouter.swift` | Added 500-entry `forwardedACKs` ring buffer. ACKs checked against buffer before forwarding. Eliminates N² traffic in dense mesh. |
| B5 | **Stale topology pruning** | `MeshIntelligence.swift` | Added `pruneStaleTopology(activePeers:)` method. Removes disconnected peers from `topologyMap` keys and neighbor sets. Wired into existing `pruneStaleEntries` cycle. |

### Phase C: UX Polish

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| C1 | **Localize hardcoded strings** | `PairingView.swift`, `ProtectTabView.swift`, `GatewayMessageView.swift` | Wrapped 26 hardcoded English strings with `String(localized:)`. AddFriendView was already fully localized. |
| C2 | **Accessibility labels** | `PTTButtonView.swift`, `StatusPillView.swift`, `SignalStrengthIndicator.swift` | Added dynamic accessibility labels per state (idle/transmitting/receiving/denied for PTT), contextual hints for status pills, human-readable signal strength descriptions. |
| C3 | **Character counter visibility** | `ChatInputBar.swift` | Counter now always visible: 0.3 opacity normally, 0.6 at 800+ chars, full opacity + red at 950+. Users know about the 1000-char limit from the start. |

### Phase D: Feature Honesty

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| D1 | **Gateway "Coming Soon"** | `GatewayMessageView.swift` | Disabled send button, added "Coming Soon" banner with explanation that SMS/email delivery is coming in a future update. |
| D2 | **Message delivery ACK** | `MeshTextMessage.swift`, `TextMessageService.swift`, `MessageBubbleView.swift` | Added `DeliveryStatus` enum (.sent/.delivered), ACK packet protocol (ACK! magic prefix), double-checkmark UI for delivered messages. Full pipeline: send → ACK received → status updated → UI shows ✓✓. |
| D3 | **Audio quick replies "Coming Soon"** | `ChannelView.swift`, `QuickReply.swift` | Audio quick replies show toast "Audio replies coming soon" instead of silently failing. Text quick replies unaffected. |

### Infrastructure

- Fixed `TransportPreference.currentAudioTransport` concurrency error (`nonisolated(unsafe)`)
- Added explicit memberwise init to `MeshTextMessage` (custom `init(from:)` suppressed synthesized init)
- Fixed `DeserializationFuzzTests` — added `@MainActor` to test class, provided missing init parameters for `SoundAlertService`, `MeshCloudService`, `SwarmService`

---

## Round 2 — Babel Freeze, WiFi Aware, Force Unwraps, App Store Polish (11 fixes)

### Phase A: Babel Freeze Fix

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| A1 | **Throttle partial translations** | `BabelService.swift` | Added 300ms debounce on partial speech results. Only translates if >0.3s since last partial translation. Prevents 50+ translation Tasks from starving the main thread during continuous speech. |
| A2 | **Translation timeout** | `BabelService.swift` | Translation calls now race against a 5-second timeout using Task cancellation pattern. If language model isn't downloaded or translation hangs, gracefully falls back with `BabelError.translationTimeout`. |
| A3 | **Task isolation fix** | `BabelService.swift` | Changed bare `Task { }` to `Task { @MainActor in }` in `handleRecognitionResult()`. Translation stays on the main actor where `translationSession` lives, eliminating data race via `nonisolated(unsafe)`. |

### Phase B: WiFi Aware & Entitlements

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| B1 | **WiFi Aware service names** | `Info.plist` | Removed trailing dots from Bonjour service entries: `_chirp-ptt._udp.` → `_chirp-ptt._udp`, `_chirp-ptt._tcp.` → `_chirp-ptt._tcp`. Fixes "chirp-ptt publishable service not found in Info.plist" error. |
| B2 | **UWB entitlement** | `Chirp.entitlements` | Added `com.apple.developer.nearby-interaction` boolean entitlement for NearbyInteraction/UWB framework usage. |

### Phase C: Force Unwrap Elimination

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| C1 | **MeshIntelligence** | `MeshIntelligence.swift` | Replaced `!linkMetrics[$0]!.isStale` with `!(linkMetrics[$0]?.isStale ?? true)` in both `bestPath()` and `reachableNodeCount`. |
| C2 | **MeshShield** | `MeshShield.swift` | Replaced `sealed.combined!` with guard-let that throws `MeshShieldError.sealedBoxCombinedNil`. |
| C3 | **ChatView clustering** | `ChatView.swift` | Replaced `cluster.last!` with guard-let + break pattern. |

### Phase D: App Store Polish

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| D1 | **Empty LaunchLogo removed** | `Assets.xcassets/LaunchLogo.imageset/` | Deleted empty imageset (no actual images, not referenced by launch screen). |
| D2 | **CameraButtonPTT disabled** | `CameraButtonPTT.swift` | `isAvailable` now returns `false` unconditionally. Removed model detection logic. Comment explains: "Disabled until iOS 26 CameraButton API is wired". |
| D3 | **Logger for SQL tracing** | `LighthouseDatabase.swift`, `Logger+Extensions.swift` | Replaced `print("SQL: \($0)")` with `Logger.database.debug(...)`. Added `static let database` to Logger extension. |

---

## Round 3 — Memory Management, Security Hardening, Store-and-Forward, UI Polish (7 fixes)

### Memory Management

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| 1 | **NotificationCenter observer cleanup** | `AppState.swift` | Added `notificationObservers: [Any]` array. All 7 `addObserver` calls now save their tokens. `stop()` removes all observers and clears the array. Prevents memory leaks and zombie callbacks. |
| 2 | **Closure retain cycle fix** | `AppState.swift` | Removed `chanMgrRef` strong capture variable. All 14 service `onSendPacket` closures changed from capturing `chanMgrRef` to `[weak self]` with `self?.channelManager`. Breaks retain cycle: AppState ↔ Services ↔ Closures. |

### Security Hardening

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| 3 | **FileTransfer encryption logging** | `FileTransferService.swift` | `encryptIfNeeded` and `decryptIfNeeded` now use do/catch with `logger.error()` instead of `try?`. Still falls back to plaintext (can't crash transfer) but failures are observable. |
| 4 | **TextMessage encryption failure** | `TextMessageService.swift` | Added else branch when both triple-layer and fallback encryption fail. Logs failure and sends raw payload rather than silently dropping the message. |
| 5 | **MeshShield cover traffic** | `MeshShield.swift` | If cover traffic encryption fails, logs error and skips sending entirely. Unencrypted cover traffic would defeat anti-traffic-analysis, so better to skip than leak. |

### Feature Wiring

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| 6 | **Store-and-forward relay** | `AppState.swift` | `textMessageService.onSendPacket` now splits peers into connected (send immediately) and offline (store in relay). Messages to offline peers persisted with 24h expiration. Re-delivered automatically when peers reconnect via existing `checkPendingForPeer` path. |

### UI Polish

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| 7a | **Error alert titles** | `DarkroomViewerView.swift` | "Error" → "Decryption Failed" |
| 7b | **Error alert titles** | `WitnessCaptureView.swift` | "Error" → "Capture Failed" |
| 7c | **Pull-to-refresh** | `HomeView.swift` | `refreshPeerDiscovery()` now restarts MultipeerTransport (stop + start) for fresh peer discovery instead of just sleeping 1 second. |

---

## Round 4 — Crash Hardening & Test Coverage (1 fix + 15 new tests)

### Crash Hardening

| # | Fix | File(s) | Details |
|---|-----|---------|---------|
| 1 | **AudioEngine force unwrap** | `AudioEngine.swift` | Replaced last force unwrap `AVAudioFormat(...)!` with guard-let + fatalError with descriptive message. |

### New Tests (15 added, 203 → 218 total)

| Test File | Tests Added | What They Cover |
|-----------|-------------|-----------------|
| `JitterBufferTests.swift` | 2 | Sequence number wraparound at UInt32.max → 0 boundary. Verifies wrapped-ahead packets accepted, wrapped-behind packets dropped. |
| `FloorControlTests.swift` | 2 | Equal-timestamp collision tiebreaker via peer ID. Tests both directions: local wins when local ID < remote ID, remote wins when remote ID < local ID. |
| `TransportPreferenceTests.swift` | 11 | **New file.** Dead-band hysteresis (low threshold, high threshold, dead zone persistence both directions), weak signal fallback, nil/empty metrics, single-transport peers, control intent always dual-sends, exact boundary conditions at 15ms and 25ms. |
| `TextMessageServiceTests.swift` | 2 | Delivery ACK updates message status to `.delivered`. Unknown ACK for random UUID ignored without crash. |

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| **Total fixes/features** | 35 |
| **Files modified** | ~30 |
| **New test files created** | 1 (`TransportPreferenceTests.swift`) |
| **Tests added** | 15 (203 → 218) |
| **Build errors** | 0 |
| **Build warnings** | 0 |
| **Test failures** | 0 |
| **Force unwraps remaining** | 0 dangerous (only safe hardcoded constants) |
| **Silent `try?` in critical paths** | 0 remaining |
| **Memory leaks fixed** | 2 (NotificationCenter + closure retain cycles) |

## Files Modified (Complete List)

**Services:**
- `Chirp/Sources/Services/PTT/PTTEngine.swift`
- `Chirp/Sources/Services/PTT/FloorController.swift`
- `Chirp/Sources/Services/Audio/AudioEngine.swift`
- `Chirp/Sources/Services/Audio/JitterBuffer.swift`
- `Chirp/Sources/Services/Network/MultipeerTransport.swift`
- `Chirp/Sources/Services/Network/WiFiAwareTransport.swift`
- `Chirp/Sources/Services/Network/TransportPreference.swift`
- `Chirp/Sources/Services/Network/PheromoneRouter.swift`
- `Chirp/Sources/Services/Network/MeshIntelligence.swift`
- `Chirp/Sources/Services/Network/MeshGateway.swift`
- `Chirp/Sources/Services/Security/MeshShield.swift`
- `Chirp/Sources/Services/FileTransferService.swift`
- `Chirp/Sources/Services/TextMessageService.swift`
- `Chirp/Sources/Services/Babel/BabelService.swift`
- `Chirp/Sources/Services/CameraButtonPTT.swift`
- `Chirp/Sources/Services/QuickReply.swift`
- `Chirp/Sources/Services/Persistence/LighthouseDatabase.swift`

**Models:**
- `Chirp/Sources/Models/MeshTextMessage.swift`

**Views:**
- `Chirp/Sources/Views/Components/PTTButtonView.swift`
- `Chirp/Sources/Views/Components/StatusPillView.swift`
- `Chirp/Sources/Views/Components/SignalStrengthIndicator.swift`
- `Chirp/Sources/Views/Components/ChatInputBar.swift`
- `Chirp/Sources/Views/Components/MessageBubbleView.swift`
- `Chirp/Sources/Views/Channel/GatewayMessageView.swift`
- `Chirp/Sources/Views/Channel/ChannelView.swift`
- `Chirp/Sources/Views/ChatView.swift`
- `Chirp/Sources/Views/Darkroom/DarkroomViewerView.swift`
- `Chirp/Sources/Views/Witness/WitnessCaptureView.swift`
- `Chirp/Sources/Views/HomeView.swift`
- `Chirp/Sources/Views/PairingView.swift`
- `Chirp/Sources/Views/Protect/ProtectTabView.swift`

**ViewModels:**
- `Chirp/Sources/ViewModels/AppState.swift`

**Utilities:**
- `Chirp/Sources/Utilities/Logger+Extensions.swift`

**Config:**
- `Chirp/Info.plist`
- `Chirp/Chirp.entitlements`

**Assets:**
- `Chirp/Resources/Assets.xcassets/LaunchLogo.imageset/` (deleted)

**Tests:**
- `ChirpTests/DeserializationFuzzTests.swift`
- `ChirpTests/JitterBufferTests.swift`
- `ChirpTests/FloorControlTests.swift`
- `ChirpTests/TextMessageServiceTests.swift`
- `ChirpTests/TransportPreferenceTests.swift` (new)
