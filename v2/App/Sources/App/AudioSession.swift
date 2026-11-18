import AVFoundation
import ChirpCore
import OSLog
import SwiftUI

/// What the adapter needs from AVAudioSession, so the moves it makes can be
/// driven by a fake. `SystemAudioSession` is the real one.
@MainActor
protocol AudioSessionPort: AnyObject {
    func configure(for need: AudioSessionNeed) throws
    func setActive(_ active: Bool) throws
}

/// The thin adapter `AudioSessionPolicy` asks for (App Review 2.5.4): it holds
/// the policy's inputs, and on every change moves the real session to what
/// `AudioSessionPolicy.need` says. It never opens anything on its own: nothing
/// at launch, nothing in the background, nothing during an interruption.
///
/// The checklist it follows is 1.0's `AudioSessionManager.swift:84-164`:
/// an interruption releases the floor and closes the session; its end only
/// clears the flag (the policy reopens on the next press or speaker); a lost
/// input device (headset unplugged) releases the floor; a media services reset
/// re-applies the current need from scratch.
@MainActor
@Observable
final class AudioSession {
    private(set) var inputs = AudioSessionInputs(foreground: false)
    /// What the real session is set to now.
    private(set) var applied: AudioSessionNeed = .off {
        didSet { if applied != oldValue { onAppliedChange?(applied) } }
    }
    /// Told every time the real session changes (the voice engine follows it).
    /// Called synchronously, inside `setFloor` when that is what moved it.
    @ObservationIgnored var onAppliedChange: ((AudioSessionNeed) -> Void)?
    /// The last failure to move the session, for the screen to explain.
    private(set) var lastError: String?

    /// Called when the floor must be let go: an interruption began, or the
    /// microphone went away. The owner of the floor releases it, which feeds
    /// back here as a new floor state.
    @ObservationIgnored var onMustReleaseFloor: (() -> Void)?

    @ObservationIgnored private let port: AudioSessionPort
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var recheckTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private static let log = Logger(subsystem: "com.jacksonmsanger.chirpchirp", category: "audio-session")

    init(port: AudioSessionPort = SystemAudioSession(), clock: @escaping () -> Date = Date.init) {
        self.port = port
        self.clock = clock
    }

    // MARK: Inputs

    func setForeground(_ foreground: Bool) { update { $0.foreground = foreground } }

    func setFloor(_ floor: FloorState) {
        update { i in
            // A speaker's turn ending starts the playback tail.
            if i.floor.speaker != nil, floor.speaker == nil { i.lastSpeechEnded = clock() }
            i.floor = floor
        }
    }

    /// Follows the scene: active is foreground, anything else is not.
    func follow(_ phase: ScenePhase) { setForeground(phase == .active) }

    private func update(_ change: (inout AudioSessionInputs) -> Void) {
        var next = inputs
        change(&next)
        guard next != inputs else { return }
        inputs = next
        apply()
    }

    // MARK: Moving the session

    private func apply() {
        let now = clock()
        let need = AudioSessionPolicy.need(inputs, now: now)
        if need != applied { move(to: need) }
        scheduleRecheck(now: now)
    }

    private func move(to need: AudioSessionNeed) {
        do {
            if need == .off {
                try port.setActive(false)
            } else {
                try port.configure(for: need)
                if applied == .off { try port.setActive(true) }
            }
            applied = need
            lastError = nil
            Self.log.info("audio session: \(String(describing: need), privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            Self.log.error("audio session to \(String(describing: need), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            // A failed open leaves nothing half open; a failed close is retried on the next change.
            if need != .off, applied == .off { try? port.setActive(false) }
            if need == .record { onMustReleaseFloor?() }
        }
    }

    private func scheduleRecheck(now: Date) {
        recheckTask?.cancel()
        guard let at = AudioSessionPolicy.recheck(inputs, now: now) else { return }
        let delay = max(0, at.timeIntervalSince(now))
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    // MARK: System notifications

    /// Call once, when the app starts. Listening opens nothing.
    func observeSystem(_ center: NotificationCenter = .default) {
        guard observers.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                                            queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.interruption(raw.flatMap(AVAudioSession.InterruptionType.init)) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session,
                                            queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { self?.routeChanged(raw.flatMap(AVAudioSession.RouteChangeReason.init)) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mediaServicesReset() }
        })
    }

    func interruption(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            Self.log.warning("interruption began: releasing the floor")
            // The system has already deactivated the session.
            applied = .off
            update { $0.interrupted = true }
            onMustReleaseFloor?()
        case .ended:
            // Whatever `shouldResume` says, nothing reopens until the policy needs it.
            update { $0.interrupted = false }
        default:
            break
        }
    }

    func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
        guard reason == .oldDeviceUnavailable, applied == .record else { return }
        Self.log.warning("input device lost while talking: releasing the floor")
        onMustReleaseFloor?()
    }

    func mediaServicesReset() {
        Self.log.warning("media services were reset: re-applying")
        applied = .off
        apply()
    }
}

/// The real AVAudioSession.
@MainActor
final class SystemAudioSession: AudioSessionPort {
    private let session = AVAudioSession.sharedInstance()

    func configure(for need: AudioSessionNeed) throws {
        switch need {
        case .record:
            // Echo cancellation, gain control and noise suppression; speaker by default, headsets allowed.
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredIOBufferDuration(0.010)
            try session.setPreferredSampleRate(16_000)
        case .playback:
            // Output only: no microphone, no orange indicator.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        case .off:
            break
        }
    }

    func setActive(_ active: Bool) throws {
        try session.setActive(active, options: active ? [] : .notifyOthersOnDeactivation)
    }
}
