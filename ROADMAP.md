# Roadmap — Chirp (BLE Walkie-Talkie)

## Next Up (conductor can pick these)
- [x] Typing indicators in chat — display "Alice typing..." bubble using existing `typingPeersByChannel` tracking. Send TYP! packet on text field onChange. Files: `Chirp/Sources/Views/ChatView.swift`, `Chirp/Sources/Views/Components/ChatInputBar.swift`
- [x] Message search within channel — add SearchField above message list, filter by substring match on text + sender, highlight matches. Files: `Chirp/Sources/Views/ChatView.swift`, `Chirp/Sources/Services/TextMessageService.swift`
- [ ] Network diagnostics view — long-press mesh radar to show peers in range, packets relayed, dedup rate, hops observed, WiFiAware link metrics. Files: `Chirp/Sources/ViewModels/AppState.swift`, new `Chirp/Sources/Views/DiagnosticsView.swift`
- [ ] Message delivery status icons — extend DeliveryStatus to include `.read`, send READ! ACK when message scrolled into view. Show checkmark progression (sent/delivered/read). Files: `Chirp/Sources/Views/Components/MessageBubbleView.swift`, `Chirp/Sources/Services/TextMessageService.swift`
- [ ] Lazy message pagination — load last 50 messages on appear, load older batches on scroll-to-top. Cap memory cache at 200 messages. Files: `Chirp/Sources/Services/Persistence/LighthouseDatabase.swift`, `Chirp/Sources/Services/TextMessageService.swift`

## Blocked (needs Jackson)
- [ ] App Store submission (needs TestFlight build, screenshots, marketing)
- [ ] WiFi Aware testing (requires iOS 26 + paired devices)

## Done
- [x] Peer ghosting detection — auto-prune peers silent for >45s
- [x] Aggressive BLE reconnection with exponential backoff and jitter
- [x] Opus in-band FEC for BLE packet loss recovery
- [x] i18n: wrapped user-facing strings with String(localized:)
- [x] PTTEngine double-send fix
- [x] CICADA steganography
- [x] Emergency SOS beacons
