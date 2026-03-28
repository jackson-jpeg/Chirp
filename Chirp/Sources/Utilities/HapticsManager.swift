import CoreHaptics
import UIKit

/// CoreHaptics-based haptic feedback manager.
/// Uses CHHapticEngine for custom haptic patterns that feel like real radio hardware.
@MainActor
final class HapticsManager: Sendable {
    static let shared = HapticsManager()

    private var engine: CHHapticEngine?
    private var engineNeedsRestart = true

    private init() {
        prepareEngine()
    }

    // MARK: - Engine Lifecycle

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true

            // Auto-restart on reset
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.engineNeedsRestart = true
                }
            }
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.engineNeedsRestart = true
                }
            }

            try engine.start()
            self.engine = engine
            self.engineNeedsRestart = false
        } catch {
            // Haptics unavailable — degrade silently
        }
    }

    private func ensureEngine() {
        guard engineNeedsRestart else { return }
        if let engine {
            do {
                try engine.start()
                engineNeedsRestart = false
            } catch {
                prepareEngine()
            }
        } else {
            prepareEngine()
        }
    }

    // MARK: - Public API

    /// Heavy thunk + sharp click — like a physical radio PTT button being depressed.
    func pttDown() {
        let events: [CHHapticEvent] = [
            // Heavy thunk — the button bottoming out
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 0
            ),
            // Brief sustain for weight
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ],
                relativeTime: 0.01,
                duration: 0.05
            ),
            // Sharp click — the latch engaging
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: 0.07
            )
        ]
        playPattern(events)
    }

    /// Light release click — button coming back up.
    func pttUp() {
        let events: [CHHapticEvent] = [
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: 0
            )
        ]
        playPattern(events)
    }

    /// Aggressive triple buzz — denied / channel busy.
    func denied() {
        let events: [CHHapticEvent] = [
            // Tap 1
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0
            ),
            // Tap 2
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.08
            ),
            // Tap 3
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: 0.16
            )
        ]
        playPattern(events)
    }

    /// Gentle notification pulse — incoming audio from peer.
    func receiving() {
        let events: [CHHapticEvent] = [
            // Soft rise
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ],
                relativeTime: 0,
                duration: 0.1
            ),
            // Gentle tap
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0.1
            )
        ]
        playPattern(events)
    }

    /// Two rising taps — a peer joined the channel.
    func peerConnected() {
        let events: [CHHapticEvent] = [
            // Low tap
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0
            ),
            // Higher tap
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0.12
            ),
            // Bright tap
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ],
                relativeTime: 0.22
            )
        ]
        playPattern(events)
    }

    /// Single falling thud — a peer left the channel.
    func peerDisconnected() {
        let events: [CHHapticEvent] = [
            // Sharp initial tap
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: 0
            ),
            // Fading rumble
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
                ],
                relativeTime: 0.05,
                duration: 0.15
            )
        ]
        playPattern(events)
    }

    // MARK: - Private

    private func playPattern(_ events: [CHHapticEvent]) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        ensureEngine()
        guard let engine else { return }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptic playback failed — not critical
        }
    }
}
