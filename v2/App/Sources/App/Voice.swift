@preconcurrency import AVFoundation
import ChirpCore
import Foundation
import Observation
import OSLog

/// Talk's floor and live voice: one ChirpCore `FloorMachine` state for the
/// channel Talk is on, its effects carried out here.
///
/// - Hold sends `.localPressed`, letting go `.localReleased`; a 1 s tick runs
///   while anyone has the line (the silence timeout and the talk cap).
/// - Floor and audio events come from `Mesh.onEvent`. Audio is played only
///   from whoever holds the floor on this channel.
/// - Every new floor state goes to `AudioSession.setFloor`, which moves the
///   real session (record while you hold, playback while someone talks and
///   for the tail after). The engine follows the session: started when it
///   opens, restarted when it changes between record and playback, stopped
///   when it closes. Nothing here opens audio by itself (2.5.4).
/// - Your frames go out through `Dispatch.audio` on the channel you pressed on.
/// - Live captions: each played speaker stream gets one `CaptionFeed`.
@MainActor
@Observable
final class Voice {
    private(set) var floor: FloorState = .idle

    /// The channel Talk is on: the demo flock, your flock, else Nearby.
    var channel: ChannelID { mesh.talkChannel }

    @ObservationIgnored private let mesh: Mesh
    @ObservationIgnored private let audio: AudioSession
    @ObservationIgnored private let captions: LiveCaptions
    @ObservationIgnored private weak var flock: Flock?
    @ObservationIgnored let engine: VoiceEngine
    /// The channel of the turn in progress (yours or someone's), so a change
    /// of flock mid-turn does not move it.
    @ObservationIgnored private var turnChannel: ChannelID?
    @ObservationIgnored private var engineMode: AudioSessionNeed = .off
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var refusal: Task<Void, Never>?
    @ObservationIgnored private let tap = CaptionTap()
    /// Your own caption's feed while the microphone is open.
    @ObservationIgnored private let mine = OwnCaptionFeed()
    private static let log = Logger(subsystem: "com.jacksonmsanger.chirpchirp", category: "voice")

    init(mesh: Mesh, audio: AudioSession, captions: LiveCaptions, flock: Flock, engine: VoiceEngine = VoiceEngine()) {
        self.mesh = mesh
        self.audio = audio
        self.captions = captions
        self.flock = flock
        self.engine = engine

        mesh.onEvent = { [weak self] e in self?.handle(e) }
        // Whoever had the line went out of range: free it now rather than
        // after the silence timeout.
        mesh.onPeerGone = { [weak self] peer in self?.reduce(.peerGone(peer)) }
        audio.onMustReleaseFloor = { [weak self] in self?.release() }
        audio.onAppliedChange = { [weak self] need in self?.follow(need) }

        // Frames leave the capture queue in order: main queue, FIFO.
        engine.onFrame = { [weak self] frame in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.sendFrame(frame) } }
        }
        let tap = self.tap
        engine.onPlayed = { [weak self] speaker, buffer in
            if tap.append(buffer, for: speaker) {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.beginCaption(speaker) } }
            }
        }
        let mine = self.mine
        engine.onCaptured = { buffer in mine.append(buffer) }
        engine.onStreamEnded = { [weak self] speaker in
            tap.remove(speaker)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.captions.end(speaker) } }
        }
    }

    // MARK: You

    /// The hold began. Refused (with a short buzz of state) if someone has the line.
    func press() {
        if floor == .idle { turnChannel = channel }
        reduce(.localPressed(at: .now))
    }

    /// Let go, slid away, an interruption, a lost microphone or the app
    /// leaving the screen. Live voice has already gone out, so a slide-away
    /// ends the turn the same way: nothing is held back to drop.
    func release() {
        // A session or engine that fails to open asks for this from inside
        // `reduce`; it runs once that turn's effects (its request) are out.
        if reducing { releaseAfter = true; return }
        reduce(.localReleased)
    }
    @ObservationIgnored private var reducing = false
    @ObservationIgnored private var releaseAfter = false

    // MARK: The line

    private func handle(_ event: Dispatch.Event) {
        switch event {
        case .floor(let m, let ch):
            // Only Talk's own channel can start a turn here; the reducer
            // ignores every other one.
            if floor == .idle, ch == channel, case .request = m { turnChannel = ch }
            reduce(.received(m, from: m.sender, channel: ch, at: .now))
        case .audio(let data, let from, let epoch, let sequence, let ch):
            reduce(.heardAudio(from: from, channel: ch, at: .now))
            guard ch == (turnChannel ?? channel), floor.speaker?.peer == from, engine.running else { return }
            engine.playsAudio = captions.playsAudio
            engine.receive(data, from: .init(peer: from, epoch: epoch), sequence: sequence)
        default:
            break
        }
    }

    private func reduce(_ event: FloorEvent) {
        guard let flock else { return }
        reducing = true
        defer {
            reducing = false
            if releaseAfter { releaseAfter = false; reduce(.localReleased) }
        }
        let out = FloorMachine.reduce(floor, on: event, me: mesh.dispatch.me, myName: flock.you.name,
                                      channel: turnChannel ?? channel)
        let speakerBefore = floor.speaker?.peer
        floor = out.state
        // Moves the session first, so the engine (through `follow`) is
        // running with the right input before the effects open the microphone.
        audio.setFloor(out.state)
        for effect in out.effects { run(effect) }
        if out.state == .idle { turnChannel = nil }
        if floor.speaker?.peer != speakerBefore { showTalker() }
        keepTicking()
    }

    private func run(_ effect: FloorEffect) {
        switch effect {
        case .openMicrophone:
            mine.set(captions.begin(me, format: OpusCodec.pcmFormat))
            engine.startCapture()
        case .closeMicrophone:
            engine.stopCapture()
            mine.set(nil)
            captions.end(me)
        case .send(let m):
            let ch = turnChannel ?? channel
            mesh.send { try $0.floor(m, on: ch, now: .now) }
        case .startRefusalTimer(let after):
            refusal?.cancel()
            refusal = Task { [weak self] in
                try? await Task.sleep(for: .seconds(after))
                guard !Task.isCancelled else { return }
                self?.reduce(.refusalExpired)
            }
        case .reportImpersonation(let claimed, let actual):
            Self.log.warning("floor message claimed \(claimed.hex, privacy: .public) but came from \(actual.hex, privacy: .public)")
        }
    }

    private func sendFrame(_ frame: Data) {
        guard floor.microphoneIsOpen, let ch = turnChannel else { return }
        mesh.send { try $0.audio(frame, on: ch, now: .now) }
    }

    /// Talk's wire and caption card read the talker from the flock.
    private func showTalker() {
        guard let flock else { return }
        flock.talkerID = floor.speaker.flatMap { s in flock.others.first { $0.peer == s.peer }?.id }
    }

    private func keepTicking() {
        if floor == .idle {
            ticker?.cancel()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.reduce(.tick(.now))
            }
        }
    }

    // MARK: Engine follows the session

    private func follow(_ need: AudioSessionNeed) {
        guard need != engineMode else { return }
        engine.stop()
        engineMode = .off
        guard need != .off else { return }
        do {
            try engine.start(input: need == .record)
            engineMode = need
        } catch {
            Self.log.error("voice engine did not start for \(String(describing: need), privacy: .public): \(error.localizedDescription, privacy: .public)")
            if need == .record { release() }
        }
    }

    // MARK: Captions

    private func beginCaption(_ speaker: JitterBuffer.Speaker) {
        tap.set(captions.begin(speaker, format: VoiceEngine.playbackFormat), for: speaker)
    }

    /// Your stream's key: this phone's PeerID and launch epoch, as other
    /// phones key your voice.
    private var me: CaptionTrack.Speaker { .init(peer: mesh.dispatch.me, epoch: mesh.dispatch.epoch) }

    /// What you are saying, live, while you hold (nil until words come, or
    /// with captions off).
    var myCaption: String? {
        guard let c = captions.track.caption(for: me), !c.text.isEmpty else { return nil }
        return c.text
    }

    /// What `who` is saying, live, if captions are on.
    func caption(of who: Person) -> String? {
        guard let peer = who.peer, let c = captions.track.latest(from: peer) else { return nil }
        return c.text.isEmpty ? nil : c.text
    }
}

/// The playback queue's view of the caption feeds: appends to a speaker's
/// feed, and says once per stream that the main actor should open one.
private final class CaptionTap: @unchecked Sendable {
    private let lock = NSLock()
    private var feeds: [JitterBuffer.Speaker: CaptionFeed] = [:]
    private var asked: Set<JitterBuffer.Speaker> = []

    /// Appends to the speaker's feed. True the first time a stream has none,
    /// so the caller asks for one.
    func append(_ buffer: AVAudioPCMBuffer, for speaker: JitterBuffer.Speaker) -> Bool {
        let (feed, ask): (CaptionFeed?, Bool) = lock.withLock {
            if let f = feeds[speaker] { return (f, false) }
            return (nil, asked.insert(speaker).inserted)
        }
        feed?.append(buffer)
        return ask
    }

    /// The feed for a stream (nil: captions are off, so nothing is appended).
    func set(_ feed: CaptionFeed?, for speaker: JitterBuffer.Speaker) {
        lock.withLock {
            guard asked.contains(speaker) else { return }   // the stream ended first
            feeds[speaker] = feed
        }
    }

    func remove(_ speaker: JitterBuffer.Speaker) {
        lock.withLock {
            feeds[speaker] = nil
            asked.remove(speaker)
        }
    }
}

/// The capture queue's view of your own caption feed.
private final class OwnCaptionFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var feed: CaptionFeed?

    /// Nil stops appending; the feed itself is ended through `LiveCaptions.end`.
    func set(_ f: CaptionFeed?) { lock.withLock { feed = f } }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { feed }?.append(buffer)
    }
}
