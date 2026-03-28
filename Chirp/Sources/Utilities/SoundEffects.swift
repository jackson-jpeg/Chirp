import AVFoundation
import Foundation

@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var phase: Double = 0.0
    private var isPlaying = false
    private var toneSequence: [(frequency: Double, duration: Double)] = []
    private var currentToneIndex = 0
    private var samplesRendered: Int = 0
    private var sampleRate: Double = 44100.0

    private init() {}

    // MARK: - Public API

    func playChirpBegin() {
        // Ascending two-tone: low then high (~200ms total)
        playTones([
            (frequency: 1200, duration: 0.10),
            (frequency: 1800, duration: 0.10)
        ])
    }

    func playChirpEnd() {
        // Descending tone (~150ms)
        playTones([
            (frequency: 1600, duration: 0.08),
            (frequency: 1000, duration: 0.07)
        ])
    }

    func playPeerJoined() {
        // Upward chime: three ascending tones
        playTones([
            (frequency: 800, duration: 0.08),
            (frequency: 1200, duration: 0.08),
            (frequency: 1600, duration: 0.10)
        ])
    }

    func playPeerLeft() {
        // Downward chime: three descending tones
        playTones([
            (frequency: 1400, duration: 0.08),
            (frequency: 1000, duration: 0.08),
            (frequency: 700, duration: 0.10)
        ])
    }

    // MARK: - Tone Engine

    private func playTones(_ tones: [(frequency: Double, duration: Double)]) {
        stopEngine()

        toneSequence = tones
        currentToneIndex = 0
        samplesRendered = 0
        phase = 0.0
        isPlaying = true

        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate

        let totalDuration = tones.reduce(0.0) { $0 + $1.duration }
        let totalSamples = Int(totalDuration * sampleRate)

        let capturedTones = tones
        var localPhase = 0.0
        var localIndex = 0
        var localRendered = 0
        let localSampleRate = sampleRate

        let sourceNode = AVAudioSourceNode(format: outputFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                if localRendered >= totalSamples {
                    for buffer in ablPointer {
                        let buf = UnsafeMutableBufferPointer<Float>(buffer)
                        buf[frame] = 0.0
                    }
                    continue
                }

                // Determine current tone
                var sampleOffset = 0
                var toneIdx = 0
                for (i, tone) in capturedTones.enumerated() {
                    let toneSamples = Int(tone.duration * localSampleRate)
                    if localRendered < sampleOffset + toneSamples {
                        toneIdx = i
                        break
                    }
                    sampleOffset += toneSamples
                }

                if toneIdx != localIndex {
                    localIndex = toneIdx
                }

                let freq = capturedTones[toneIdx].frequency
                let amplitude: Float = 0.3

                // Fade envelope for click-free audio
                let toneSamples = Int(capturedTones[toneIdx].duration * localSampleRate)
                let posInTone = localRendered - sampleOffset
                let fadeLen = min(100, toneSamples / 4)
                var envelope: Float = 1.0
                if posInTone < fadeLen {
                    envelope = Float(posInTone) / Float(fadeLen)
                } else if posInTone > toneSamples - fadeLen {
                    envelope = Float(toneSamples - posInTone) / Float(fadeLen)
                }

                let sample = Float(sin(localPhase * 2.0 * .pi)) * amplitude * envelope
                localPhase += freq / localSampleRate
                if localPhase > 1.0 { localPhase -= 1.0 }

                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = sample
                }

                localRendered += 1
            }

            return noErr
        }

        self.sourceNode = sourceNode
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: outputFormat)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            self.audioEngine = engine

            // Auto-stop after playback completes
            let stopDelay = totalDuration + 0.05
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(stopDelay))
                self?.stopEngine()
            }
        } catch {
            print("SoundEffects: Failed to start audio engine: \(error)")
        }
    }

    private func stopEngine() {
        audioEngine?.stop()
        if let node = sourceNode {
            audioEngine?.detach(node)
        }
        sourceNode = nil
        audioEngine = nil
        isPlaying = false
    }
}
