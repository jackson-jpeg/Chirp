# CHIRPCHIRP V2 — THE MESH REVOLUTION

## Implementation Plan for Claude Code

**Document Purpose:** This is the master orchestration plan for Claude Code to build ChirpChirp V2. Claude Code acts as the **conductor** — reading this plan, spawning Opus 4.6 subagents for parallel workstreams, and integrating their output. Each phase has clearly scoped subagent tasks marked with `🤖 SUBAGENT TASK`.

**The Vision:** ChirpChirp is not a walkie-talkie app. It is an **infrastructure-free communication network** that turns every iPhone into a relay node. When governments kill the internet, when hurricanes flatten cell towers, when 80,000 people pack a stadium and cellular collapses, when you can't afford a phone plan — ChirpChirp still works. Every device that installs ChirpChirp extends the network for everyone else. The mesh IS the infrastructure.

**What we have today:** A working PTT app with Opus audio, MultipeerConnectivity transport, mesh packet routing with TTL-based forwarding, floor control, E2E encryption, emergency SOS beacons, friends system, live transcription, voice message queue, Live Activity, and a polished SwiftUI interface. The foundation is strong. Now we build the revolution on top of it.

---

## ARCHITECTURE PRINCIPLES

Before any code is written, every subagent must internalize these:

1. **Every device is a relay.** There is no client/server. Every ChirpChirp device forwards every packet it receives (minus TTL) to every peer it can reach. The network grows with every install.

2. **Offline-first, always.** No feature may require internet. If internet is available, it's a bonus (mesh gateway), never a requirement.

3. **Bandwidth is sacred.** Mesh links are ~1-20 Mbps shared across all peers. Every byte counts. Prefer Opus voice (3 KB/s) over raw audio (32 KB/s). Prefer compressed text (bytes) over voice. Prefer delta updates over full state.

4. **Privacy is non-negotiable.** All channel communication is E2E encrypted with AES-GCM-256. Peer identity is Ed25519 keypairs stored in Keychain. No metadata leaks. The mesh router cannot read packet payloads — only headers.

5. **The app must be unkillable in the background.** During emergencies, people can't keep the app foregrounded. The silent audio + BGTask keep-alive system must be bulletproof.

6. **Degrade gracefully.** If only 2 devices are in range, it's a walkie-talkie. If 200 are, it's a city-wide mesh. The UX adapts to the mesh size without configuration.

---

## PHASE 0: TRANSPORT UNIFICATION (Critical Foundation)

**Why first:** The codebase currently has two transport paths (MultipeerTransport + ConnectionManager) that overlap, causing potential double-delivery and encoding mismatches. Every feature in V2 depends on a single, clean packet flow. Fix this before building anything else.

### 🤖 SUBAGENT TASK 0.1: Unify Packet Flow

**Scope:** Refactor so ALL packets (audio + control) flow through MeshRouter, regardless of transport.

**Current problem:**
- PTTEngine sends via BOTH `multipeerTransport?.sendAudio()` AND `connectionManager.sendAudio()`
- AppState has duplicate `Task` blocks consuming `multipeerTransport.audioPackets` and `multipeerTransport.controlMessages` — these are ALSO consumed by the mesh router's `onLocalDelivery`, causing double processing
- MultipeerTransport has both mesh (magic byte 0xAA) and legacy (raw type byte) code paths

**Required changes:**

1. **Remove the legacy (non-mesh) code path from MultipeerTransport entirely.** Every `sendAudio()` and `sendControl()` call must wrap in a MeshPacket. Every received packet must be deserialized as a MeshPacket and routed through MeshRouter. Delete the `PacketType` enum and the legacy branch in `session(didReceive:)`.

2. **Remove the duplicate stream consumers in AppState.** The two `Task` blocks that consume `multipeerTransport.audioPackets` and `multipeerTransport.controlMessages` must be deleted. All delivery happens via `meshRouter.onLocalDelivery`.

3. **PTTEngine should only send through one path.** Remove the `connectionManager.sendAudio()` and `connectionManager.sendControl()` calls from PTTEngine's callbacks. All sends go through MultipeerTransport (which wraps in MeshPacket). ConnectionManager becomes dormant scaffolding for future Wi-Fi Aware activation.

4. **Add channel filtering in the mesh router's local delivery callback.** In AppState's `onLocalDelivery` closure, check `packet.channelID` against `channelManager.activeChannel?.id`. Drop audio packets for other channels. Control packets with empty channelID (broadcasts like SOS, beacons) are always delivered.

5. **Standardize JSON encoding.** Create a shared `MeshCodable` utility with a single `JSONEncoder` (`.iso8601` date strategy, `.sortedKeys`) and `JSONDecoder` used everywhere — MultipeerTransport, ConnectionManager, FloorController, MeshBeacon, EmergencyBeacon. No more inconsistent encoding.

**Files to modify:** `MultipeerTransport.swift`, `PTTEngine.swift`, `AppState.swift`, `MeshRouter.swift`
**Files to create:** `Utilities/MeshCodable.swift`
**Tests to add:** `MeshPacketTests.swift` (serialize/deserialize round-trip, forwarded TTL decrement, channel filtering)

---

### 🤖 SUBAGENT TASK 0.2: Heartbeat System

**Scope:** Implement active heartbeat broadcasting so the mesh knows who's alive.

PTTEngine should broadcast a `FloorControlMessage.heartbeat` every 5 seconds while in an active channel. PeerTracker's health check (already runs every 5 seconds) marks peers stale after 15 seconds without a heartbeat. When a peer goes stale, ChannelView shows a disconnect toast and removes them from the peer circle.

Also wire `MultipeerTransport.onPeersChanged` to send `.peerJoin` when a new MC peer connects and `.peerLeave` when one disconnects, so the floor controller can release the floor if the speaker leaves.

**Files to modify:** `PTTEngine.swift`, `AppState.swift`, `ChannelView.swift`

---

## PHASE 1: TEXT MESH — THE BACKBONE

**Why:** Voice uses ~3 KB/s per sender. Text uses bytes. In a bandwidth-constrained mesh with dozens of relays, text messaging is 1000x more efficient. During an emergency, a text saying "trapped in building C, floor 3" is more actionable than a noisy voice message. Text is also silent — critical when hiding from danger.

### 🤖 SUBAGENT TASK 1.1: MeshTextMessage Model + Protocol

**Scope:** Design the text message data model and wire format.

```swift
struct MeshTextMessage: Codable, Sendable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let channelID: String
    let text: String              // Max 1000 chars
    let timestamp: Date
    let replyToID: UUID?          // Thread support
    let attachmentType: AttachmentType?

    enum AttachmentType: String, Codable, Sendable {
        case location              // Embedded lat/lon
        case image                 // Compressed thumbnail (max 50KB)
        case contact               // Peer identity card
    }
}
```

Text messages are sent as MeshPacket type `.control` with a new magic prefix (`TXT!`) to distinguish from floor control messages. They flow through the same mesh relay infrastructure. Channel encryption applies — messages for locked channels are AES-GCM encrypted before entering the mesh.

Create `TextMessageService` that:
- Sends text messages via MultipeerTransport wrapped in MeshPacket
- Receives text messages via MeshRouter's onLocalDelivery
- Stores message history per channel in a local SQLite database (NOT UserDefaults — messages can be large)
- Handles deduplication (same message arriving via multiple mesh paths)
- Supports replies (thread model with `replyToID`)

**Files to create:** `Models/MeshTextMessage.swift`, `Services/TextMessageService.swift`
**Dependencies:** Add `GRDB.swift` or use raw SQLite via `sqlite3` C API for local message storage (GRDB is cleaner, available via SPM)

---

### 🤖 SUBAGENT TASK 1.2: Chat UI

**Scope:** Build a full chat interface for each channel, sitting alongside the PTT interface.

ChannelView gets a segmented mode: **Talk** (existing PTT UI) and **Chat** (text messages). The chat view follows iMessage-style layout:
- Messages from self on the right (amber bubbles)
- Messages from others on the left (dark gray bubbles, sender name above)
- Timestamps grouped by time proximity
- Reply threading (tap a message to reply, shows quoted text above)
- Location attachment renders as a mini map pin with coordinates
- Scroll-to-bottom FAB when new messages arrive while scrolled up
- Message input bar at bottom with send button + attachment menu (location pin, image)

The input bar has a character counter (1000 max) and shows the estimated hop count to give users a sense of how far their message will travel.

**Files to create:** `Views/ChatView.swift`, `Views/Components/MessageBubbleView.swift`, `Views/Components/ChatInputBar.swift`, `Views/Components/LocationAttachmentView.swift`
**Files to modify:** `ChannelView.swift` (add segmented mode switcher)

---

### 🤖 SUBAGENT TASK 1.3: Location Sharing

**Scope:** Let users drop their GPS pin into a channel with one tap.

A "Share Location" button in the chat input bar captures the current CLLocation, creates a MeshTextMessage with `.location` attachment type, and embeds `latitude` and `longitude` in the text field as a structured string (e.g., `LOC:27.9506,-82.4572,12.5` for lat, lon, accuracy).

On the receiving end, `LocationAttachmentView` parses this and renders:
- Coordinates in monospace
- Distance from the viewer's location (using CLLocation.distance)
- Compass bearing arrow pointing toward the sender
- "Open in Maps" button (works offline if Apple Maps has cached tiles)

This is critical for: search and rescue, finding friends at festivals, emergency rendezvous points.

**Files to create:** `Views/Components/LocationAttachmentView.swift`, `Services/LocationService.swift`

---

## PHASE 2: MESH INTELLIGENCE — MAKE THE NETWORK SMARTER

**Why:** A dumb mesh floods every packet everywhere. A smart mesh routes efficiently, preserves battery, extends range, and self-heals. This phase turns ChirpChirp from a broadcast network into an intelligent routing fabric.

### 🤖 SUBAGENT TASK 2.1: Adaptive TTL + Smart Relay

**Scope:** Make relay decisions intelligent based on real conditions.

Currently MeshRouter uses a fixed default TTL of 4 and every device blindly relays everything. Upgrade to:

**Adaptive TTL based on message type:**
- SOS/Emergency: TTL 8 (maximum reach, non-negotiable)
- Voice audio: TTL 2 (voice is real-time, old audio is useless after 2 hops)
- Text messages: TTL 6 (text is durable, should propagate widely)
- Beacons: TTL 4 (presence info, medium propagation)
- Location shares: TTL 6 (critical info, wide propagation)

**Smart relay decisions in MeshIntelligence:**
- If device battery < 10%, only relay SOS packets
- If device battery < 20%, only relay SOS + text (skip audio relay)
- If a packet has been seen from 3+ paths already (high redundancy), reduce relay priority
- Track packet delivery success rate per peer link; prefer relaying through high-quality links
- Implement basic congestion detection: if the outbound queue exceeds 50 packets, drop lowest-priority audio packets first

**Mesh density awareness:**
- Count unique peer IDs seen in beacons within the last 10 seconds
- If mesh is dense (>10 peers visible), reduce beacon frequency to every 5 seconds to save airtime
- If mesh is sparse (<3 peers), increase beacon frequency to every 1 second to improve discovery

**Files to modify:** `MeshRouter.swift`, `MeshIntelligence.swift`, `MeshBeacon.swift`, `MeshPacket.swift` (add message priority field)

---

### 🤖 SUBAGENT TASK 2.2: Mesh Topology Visualization Upgrade

**Scope:** Transform MeshMapView from a simple peer circle into a real-time topology map that shows the actual mesh network.

Upgrade MeshMapView to:
- Show multi-hop paths: if Peer A can reach Peer C through Peer B, draw the chain A→B→C
- Animate data pulses flowing along the links when packets are relayed
- Color-code links by quality (green = strong, amber = degraded, red = weak)
- Show estimated range rings (each hop ≈ 30-80m depending on environment)
- Display mesh health score (from MeshIntelligence) prominently
- Show packet stats: relayed/delivered/deduplicated as live counters
- When an SOS is active anywhere in the mesh, pulse the entire map red and show the SOS sender's position

The topology data comes from MeshBeacon — each beacon includes the sender's known peer list, which MeshIntelligence assembles into a topology graph.

**Files to modify:** `MeshMapView.swift`, `MeshBeacon.swift` (include neighbor list in beacon payload), `MeshIntelligence.swift` (expose topology graph)

---

### 🤖 SUBAGENT TASK 2.3: Mesh Gateway — Bridge to the Internet

**Scope:** If ONE device in the mesh has cellular/WiFi internet, let it relay messages to the outside world for the entire mesh.

This is the killer feature for emergency scenarios. Imagine 50 people in a disaster zone with no cell service — but one person on the edge of the zone gets a single bar of signal. That person's ChirpChirp becomes a **gateway node**, and everyone in the mesh can send text messages to phone numbers or a web dashboard.

Implementation:
- Create `MeshGateway` service that detects when the device has internet connectivity (NWPathMonitor)
- When internet is available, the device broadcasts a special beacon type: `gatewayAvailable`
- Other devices see this beacon and gain a "Send to Outside" option in the chat UI
- Gateway messages are text-only (bandwidth conservation) with a recipient phone number or email
- The gateway device POSTs the message to a lightweight Vercel/Railway API endpoint (you already have this infra from your other projects)
- The API endpoint sends an SMS via Twilio or email via SendGrid
- Responses come back through the same path: API → push notification to gateway device → mesh broadcast back to originator

For V2 MVP, the gateway can be text-out only (one-way). Bidirectional can come later.

**Files to create:** `Services/Network/MeshGateway.swift`, `Views/GatewayMessageView.swift`
**Backend to create:** A simple Vercel API route: `POST /api/gateway` that accepts `{from, to, message}` and sends via Twilio. Jackson already has Vercel infra from SoGoJet/Sanger — reuse it.

---

## PHASE 3: RESILIENCE — MAKE IT UNKILLABLE

**Why:** In the scenarios ChirpChirp is built for, the app MUST keep working. Government shutdowns last days. Hurricanes last hours. People can't babysit their phones.

### 🤖 SUBAGENT TASK 3.1: Bulletproof Background Execution

**Scope:** Harden the background mesh keep-alive to survive every iOS background killing scenario.

Current implementation uses silent audio playback + BGAppRefreshTask. Upgrade:

- **Audio session interruption handling:** When a phone call, Siri, or another app takes the audio session, gracefully pause PTT and resume when the interruption ends. Register for `AVAudioSession.interruptionNotification` and `.routeChangeNotification` in AudioSessionManager. PTTEngine should auto-release the floor on interruption and show a toast on resume.

- **Silent audio robustness:** The current silent WAV generation works but iOS can detect truly silent audio and may deprioritize. Generate audio with an inaudible 20Hz tone at -60dB instead of pure silence. This is technically "playing audio" and iOS will respect the background mode.

- **Network change resilience:** When WiFi/cellular toggles (common during emergencies), MultipeerConnectivity sessions can break. Implement auto-reconnection: when `onPeersChanged` drops to 0, wait 2 seconds, then restart advertising + browsing. Exponential backoff if it keeps failing (2s, 4s, 8s, max 30s).

- **Low power mode awareness:** When iOS Low Power Mode activates, reduce beacon frequency, disable live transcription, and show a banner suggesting the user keep ChirpChirp foregrounded for best reliability.

- **Crash recovery:** Persist the active channel ID and PTT state to UserDefaults. On app launch, if there was an active channel, auto-rejoin it silently and restart the mesh. The user shouldn't have to manually reconnect after a crash or force-quit.

**Files to modify:** `BackgroundMeshService.swift`, `AudioSessionManager.swift`, `PTTEngine.swift`, `AppState.swift`, `MultipeerTransport.swift`

---

### 🤖 SUBAGENT TASK 3.2: Store-and-Forward Message Relay

**Scope:** When a device can't reach the recipient directly, store messages and forward them when the recipient comes into range.

VoiceMessageQueue already has the storage infrastructure. Extend it to handle text messages too, and make the relay automatic:

- When a text message arrives via mesh but the recipient is not in the local peer list, store it in a `PendingRelay` table
- Every time a new peer connects, check if any pending relay messages are addressed to them
- If so, forward the message immediately
- Add a `relayedBy` field to MeshTextMessage so the recipient can see the message was store-and-forwarded
- Messages expire after 24 hours to prevent unbounded storage growth
- Show relay stats in the debug overlay: "Relaying X messages for Y peers"

This turns every device into a **delay-tolerant network node**. Even if two people are never in range simultaneously, their messages can still reach each other through intermediate devices over time.

**Files to create:** `Services/StoreAndForwardRelay.swift`
**Files to modify:** `VoiceMessageQueue.swift`, `MeshRouter.swift`, `AppState.swift`

---

### 🤖 SUBAGENT TASK 3.3: Emergency Mode

**Scope:** A single toggle that optimizes the entire app for emergency/disaster scenarios.

When Emergency Mode is activated (long-press the SOS button or toggle in settings):

**Battery conservation:**
- Disable all UI animations
- Reduce mesh beacon to every 10 seconds
- Disable live transcription
- Set audio to minimum quality (8kbps Opus, still intelligible)
- Dim screen brightness recommendation
- Show estimated battery life remaining at current mesh usage rate

**Maximum mesh range:**
- Increase default TTL to 8 for all message types
- Enable aggressive relay (relay everything, ignore battery thresholds)
- Broadcast own location every 30 seconds automatically
- Enable the SOS beacon

**Communication priority:**
- Text messages get priority over voice in the relay queue
- Location shares get highest priority after SOS
- Voice audio packets get lowest relay priority (still transmitted locally, just not relayed as far)

**Emergency channel:**
- Auto-create or join a special "EMERGENCY" channel with no encryption (so everyone can hear)
- All devices in Emergency Mode auto-join this channel
- Messages on this channel propagate at max TTL regardless of settings

**UI changes:**
- Red-tinted interface throughout
- Battery percentage always visible
- Mesh node count always visible
- Persistent "EMERGENCY MODE" banner
- One-tap location share button always visible
- Simplified PTT button (larger, no animations to save CPU)

**Files to create:** `Services/EmergencyMode.swift`, `Views/EmergencyModeOverlay.swift`
**Files to modify:** `AppState.swift`, `MeshRouter.swift`, `MeshBeacon.swift`, `PTTEngine.swift`, `OpusCodec.swift` (add configurable bitrate), `ChannelView.swift`, `HomeView.swift`

---

## PHASE 4: ACCESSIBILITY & INCLUSION

**Why:** ChirpChirp must work for everyone. Delaney's work with visually impaired students proves this isn't optional — it's core to the mission.

### 🤖 SUBAGENT TASK 4.1: Full VoiceOver + Accessibility Audit

**Scope:** Make every screen fully navigable with VoiceOver, Dynamic Type, and reduced motion.

- Add `accessibilityLabel`, `accessibilityHint`, and `accessibilityValue` to every interactive element
- The PTT button must announce "Hold to talk. Double tap and hold." for VoiceOver users
- Peer avatars must announce name, connection status, and signal strength
- Channel cards must announce name, peer count, and active status
- Waveform visualizations need `accessibilityElement(children: .ignore)` with a summary label like "Audio active, input level 60%"
- All animations must respect `UIAccessibility.isReduceMotionEnabled` — replace with crossfades
- All text must support Dynamic Type up to AX5 (test at every size)
- The mesh map must have a non-visual alternative: a sorted list of nodes with distance and hop count, accessible via VoiceOver rotor

**Files to modify:** Every View file. This is a full audit. Create an `AccessibilityIdentifiers.swift` constants file for test automation.

---

### 🤖 SUBAGENT TASK 4.2: Language + Localization Foundation

**Scope:** Extract all user-facing strings into a Localizable.xcstrings catalog.

Even for V2 MVP (English only), this is the right time to do it — before the string count grows further. Create `Localizable.xcstrings` with every user-facing string. Use String(localized:) throughout. Priority languages for post-launch: Spanish, Arabic, Farsi, Ukrainian, Burmese, Chinese — these are the languages of people who need ChirpChirp most.

**Files to create:** `Resources/Localizable.xcstrings`
**Files to modify:** Every View file (replace hardcoded strings)

---

## PHASE 5: POLISH & SHIP

### 🤖 SUBAGENT TASK 5.1: Wire Existing Features into ChannelView

**Scope:** Several built features exist but aren't connected to the UI.

- **TranscriptOverlayView:** Show at top of ChannelView when `pttState == .receiving`. In PTTEngine's receive path, when audio packets arrive and floor state is receiving, feed the decoded PCM buffers to `LiveTranscription.feedInt16Buffer()`. When floor releases, call `stopTranscribing()`. The overlay auto-hides after 3 seconds (already implemented).

- **QuickReplyBar:** Show horizontally scrollable bar above the PTT button (below the waveform). Wire `onTap` to: take the floor, speak the reply via TTS routed through the Opus encoder, release the floor. For V2, the TTS audio should feed directly into the AudioEngine's capture pipeline rather than playing through the speaker.

- **DebugOverlayView:** Add `.debugOverlay()` modifier to ChannelView. Already exists as a modifier — just apply it.

- **ProximityAlert:** Wire `MultipeerTransport.onPeersChanged` to call `ProximityAlert.checkProximity()` in AppState. Show proximity alert toasts in HomeView.

**Files to modify:** `ChannelView.swift`, `PTTEngine.swift`, `AppState.swift`, `HomeView.swift`

---

### 🤖 SUBAGENT TASK 5.2: App Icon Generation

**Scope:** Generate a production 1024x1024 PNG app icon from the chosen bird design concept.

The repo has `icon.svg` (angular bird on dark background with signal arcs). If Jackson has chosen a different concept from our exploration (Perched Pair, Songbird Stack, etc.), update accordingly. The icon must:
- Export as exactly 1024x1024 PNG
- Have no transparency (iOS requirement)
- Be placed at `Chirp/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png`
- Look good at 60x60 (home screen), 40x40 (settings), and 29x29 (spotlight) sizes
- Contents.json already references `icon_1024.png` — just generate the file

Use a Python script with `cairosvg` or `Pillow` to render SVG → PNG at 1024x1024.

---

### 🤖 SUBAGENT TASK 5.3: Onboarding V2 — Communicate the Mission

**Scope:** Update OnboardingView to communicate what makes ChirpChirp different.

Current onboarding has three pages: Pair, Talk, Secure. For V2, add context about WHY:

- **Page 1: "No towers. No internet. No problem."** — Animated illustration showing cell towers going dark and ChirpChirp devices lighting up in a mesh pattern. Explain that ChirpChirp works when nothing else does.

- **Page 2: "Every phone extends the network."** — Animated illustration showing mesh growing as more devices join. Explain the relay concept in one sentence: "Your phone helps others communicate, and theirs helps you."

- **Page 3: "Talk or text."** — Show the PTT button and chat interface side by side. Voice for speed, text for stealth and efficiency.

- **Page 4: "Private by default."** — Lock icon with encryption visualization. "End-to-end encrypted. No servers. No accounts. No data collection. Ever."

- **Page 5: "Built for when it matters most."** — Show use cases: natural disasters, concerts, travel, protests, off-grid adventures. Get Started button.

**Files to modify:** `OnboardingView.swift`

---

### 🤖 SUBAGENT TASK 5.4: TestFlight Build Pipeline

**Scope:** Get a clean build that archives and uploads to TestFlight.

- Verify `project.yml` generates a valid Xcode project via `xcodegen`
- Ensure all `#if canImport(WiFiAware)` guards compile cleanly on current Xcode (WiFiAware won't be available until Xcode 26 beta)
- Ensure all `#if canImport(DeviceDiscoveryUI)` guards work
- Run full test suite: `AudioPacketTests`, `FloorControlTests`, `FloorControlMessageTests`, `JitterBufferTests`, `PTTStateTests` + new `MeshPacketTests`
- Fix any Swift 6 strict concurrency warnings
- Archive for App Store distribution
- Upload to App Store Connect / TestFlight
- Write TestFlight release notes

---

## PHASE 6: POST-LAUNCH VISION (Future Backlog)

These are documented for future planning. Do NOT implement in V2 — but design the current architecture so they're possible.

### 6.1 Image Sharing Over Mesh
Compress images to <50KB JPEG thumbnails and send as MeshTextMessage attachments. At 3KB/s mesh throughput, a 50KB image takes ~17 seconds to transfer across one hop. Acceptable for emergencies. Use progressive JPEG so partial transfers still show something.

### 6.2 Mesh-Based Group Video (Low-res)
One sender captures 160x120 MJPEG at 2fps, Opus-encoded audio alongside. This fits in ~15KB/s — within mesh bandwidth. Useful for showing conditions in a disaster zone. NOT a video call — one-way broadcast like PTT but with video.

### 6.3 Offline Maps Integration
Bundle a lightweight vector tile set for the user's region. When location is shared over the mesh, render it on the offline map. Use MapLibre GL (you already used this for Paulett) with OpenFreeMap tiles cached on-device.

### 6.4 Cross-Platform Android App
Wi-Fi Aware is a Wi-Fi Alliance standard — Android has supported it since Android 8.0 via `WifiAwareManager`. A React Native or native Kotlin companion app could join the same mesh network. The wire protocol (MeshPacket) is platform-agnostic by design — it's just bytes.

### 6.5 Dedicated Hardware: ChirpChirp Relay Node
A Raspberry Pi Zero W running a headless ChirpChirp relay daemon. Place them around a festival/campus/neighborhood to extend the mesh permanently. Solar-powered for disaster preparedness. The mesh protocol doesn't care what device is relaying — just that the packets are correctly formatted.

### 6.6 Stealth Mode
For users in authoritarian regimes: hide ChirpChirp behind a calculator or notes app facade. Disguise mesh traffic as standard Bonjour/mDNS discovery. No visible notifications. Plausible deniability mode where all message history is wiped on a specific gesture (three-finger swipe down).

### 6.7 Mesh Analytics Dashboard
A web dashboard (Next.js — Jackson's wheelhouse) that gateway nodes can optionally report anonymized mesh statistics to: node count over time, geographic spread, message volume, average hop count. Useful for disaster response coordination. Completely opt-in.

---

## CLAUDE CODE ORCHESTRATION GUIDE

### How to Execute This Plan

Claude Code should work through the phases sequentially (Phase 0 → 1 → 2 → 3 → 4 → 5). Within each phase, subagent tasks CAN be parallelized where they don't share file dependencies.

### Subagent Spawning Strategy

For each `🤖 SUBAGENT TASK`, Claude Code should:

1. **Read the task scope** and identify all files to create/modify
2. **Spawn an Opus 4.6 subagent** with a focused prompt containing:
   - The specific task description from this document
   - The current content of all files the task touches (read them first)
   - The architecture principles from the top of this document
   - Explicit instruction: "Return the complete implementation. Every file, every line. Production quality. Swift 6 strict concurrency. Comprehensive error handling. OSLog logging."
3. **Review the subagent output** before applying it. Check for:
   - Does it respect the existing code patterns (e.g., `@Observable`, `Logger` categories, `Constants` references)?
   - Does it handle errors gracefully with user-facing feedback?
   - Does it have proper `Sendable` conformance for actor isolation?
   - Does it use the amber/red/green color palette from Constants.Colors?
4. **Integrate** the output, resolve any merge conflicts with other subagent work
5. **Build and test** after each integration

### Parallel Execution Map

```
PHASE 0 (sequential — foundational):
  0.1 Transport Unification ──→ 0.2 Heartbeat System

PHASE 1 (parallel after 0):
  1.1 Text Message Model ──→ 1.2 Chat UI (depends on 1.1)
                           ──→ 1.3 Location Sharing (depends on 1.1)

PHASE 2 (parallel after 1):
  2.1 Adaptive TTL ──┐
  2.2 Mesh Map     ──┤── can run in parallel
  2.3 Mesh Gateway ──┘

PHASE 3 (parallel after 2):
  3.1 Background Hardening ──┐
  3.2 Store-and-Forward    ──┤── can run in parallel
  3.3 Emergency Mode       ──┘   (3.3 depends on 2.1 for adaptive TTL)

PHASE 4 (parallel, any time after 0):
  4.1 Accessibility Audit ──┐
  4.2 Localization        ──┘── can run in parallel with anything

PHASE 5 (sequential, after all above):
  5.1 Wire Features → 5.2 App Icon → 5.3 Onboarding V2 → 5.4 TestFlight
```

### Testing Requirements Per Phase

Every subagent task that creates new service classes must include unit tests. Minimum coverage:

- **Phase 0:** MeshPacket round-trip test, channel filtering test, encoding consistency test
- **Phase 1:** TextMessageService send/receive/dedup test, MeshTextMessage Codable round-trip, SQLite storage CRUD test
- **Phase 2:** Adaptive TTL selection test, relay decision test (battery levels), congestion detection test
- **Phase 3:** Store-and-forward relay test (queue → connect → deliver), Emergency Mode state transitions test
- **Phase 5:** Integration test: send text message → relay through mock mesh → receive and display

### File Naming Conventions

- Services: `Services/{Category}/{ServiceName}.swift`
- Models: `Models/{ModelName}.swift`
- Views: `Views/{ViewName}.swift`
- Components: `Views/Components/{ComponentName}.swift`
- Tests: `ChirpTests/{TestName}Tests.swift`
- Utilities: `Utilities/{UtilityName}.swift`

### Commit Message Convention

```
[Phase.Task] Brief description

Examples:
[0.1] Unify transport — all packets flow through MeshRouter
[1.1] Add MeshTextMessage model and TextMessageService
[2.3] Implement mesh gateway with Vercel relay endpoint
[3.3] Emergency Mode — battery conservation + max range + auto-channel
```

---

## THE NORTH STAR

When a hurricane hits Tampa and the cell towers go down, Jackson opens ChirpChirp. His neighbor has it too. And their neighbor. And the person three blocks away. Within minutes, a mesh network spanning the neighborhood is alive — no infrastructure required. People share locations ("water at Bayshore & Gandy"), coordinate rescues ("family trapped at 4th floor, 2201 W Platt"), and send text messages to family outside the disaster zone through a single gateway device that found a bar of signal.

That's what we're building. Every line of code serves this mission.

Build it.
