import AudioToolbox
import AVFoundation
import Foundation

/// Generates Nextel-style chirp tones using AVAudioEngine with a SEPARATE .ambient
/// audio session category so it layers on top without disrupting the main
/// AudioEngine's .playAndRecord session.
@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    private var toneEngine: AVAudioEngine?
    private var tonePlayerNode: AVAudioPlayerNode?
    private var isEngineRunning = false

    private init() {}

    // MARK: - Public API

    /// Classic Nextel ascending two-tone "chirp-chirp" (~200ms).
    /// Two quick tones: low then high, with a tiny gap.
    func playChirpBegin() {
        let sampleRate: Double = 44100
        // Tone 1: ~1200 Hz for 70ms
        // Gap: ~30ms
        // Tone 2: ~1800 Hz for 90ms
        // Total: ~190ms
        let tone1Duration = 0.070
        let gapDuration = 0.030
        let tone2Duration = 0.090
        let totalDuration = tone1Duration + gapDuration + tone2Duration

        let buffer = generateChirpBuffer(
            sampleRate: sampleRate,
            segments: [
                ToneSegment(frequency: 1200, duration: tone1Duration, amplitude: 0.35),
                ToneSegment(frequency: 0, duration: gapDuration, amplitude: 0), // gap
                ToneSegment(frequency: 1800, duration: tone2Duration, amplitude: 0.35)
            ],
            totalDuration: totalDuration,
            fadeMs: 5
        )

        playBuffer(buffer)
    }

    /// Single descending tone (~150ms).
    func playChirpEnd() {
        let sampleRate: Double = 44100
        let totalDuration = 0.130

        // Descending sweep from ~1600 Hz down to ~900 Hz
        let buffer = generateSweepBuffer(
            sampleRate: sampleRate,
            startFreq: 1600,
            endFreq: 900,
            duration: totalDuration,
            amplitude: 0.30,
            fadeMs: 5
        )

        playBuffer(buffer)
    }

    /// System positive chime — peer joined.
    func playPeerJoined() {
        AudioServicesPlaySystemSound(1025)
    }

    /// System negative tone — peer left.
    func playPeerLeft() {
        AudioServicesPlaySystemSound(1073)
    }

    // MARK: - Tone Generation

    private struct ToneSegment {
        let frequency: Double
        let duration: Double
        let amplitude: Float
    }

    /// Generates a buffer containing concatenated tone segments with fade in/out.
    private func generateChirpBuffer(
        sampleRate: Double,
        segments: [ToneSegment],
        totalDuration: Double,
        fadeMs: Double
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let totalFrames = AVAudioFrameCount(totalDuration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buffer.frameLength = totalFrames

        guard let channelData = buffer.floatChannelData?[0] else { return buffer }

        let fadeSamples = Int(fadeMs / 1000.0 * sampleRate)
        var writeIndex = 0

        for segment in segments {
            let segmentFrames = Int(segment.duration * sampleRate)

            for i in 0..<segmentFrames {
                guard writeIndex < Int(totalFrames) else { break }

                var sample: Float = 0
                if segment.frequency > 0 {
                    let phase = 2.0 * Double.pi * segment.frequency * Double(i) / sampleRate
                    sample = segment.amplitude * Float(sin(phase))

                    // Apply fade envelope
                    if i < fadeSamples {
                        sample *= Float(i) / Float(fadeSamples)
                    } else if i > segmentFrames - fadeSamples {
                        let remaining = segmentFrames - i
                        sample *= Float(remaining) / Float(fadeSamples)
                    }
                }

                channelData[writeIndex] = sample
                writeIndex += 1
            }
        }

        // Zero any remaining frames
        while writeIndex < Int(totalFrames) {
            channelData[writeIndex] = 0
            writeIndex += 1
        }

        return buffer
    }

    /// Generates a frequency sweep buffer (descending tone).
    private func generateSweepBuffer(
        sampleRate: Double,
        startFreq: Double,
        endFreq: Double,
        duration: Double,
        amplitude: Float,
        fadeMs: Double
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let totalFrames = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buffer.frameLength = totalFrames

        guard let channelData = buffer.floatChannelData?[0] else { return buffer }

        let fadeSamples = Int(fadeMs / 1000.0 * sampleRate)
        var phase: Double = 0

        for i in 0..<Int(totalFrames) {
            // Linear frequency interpolation
            let t = Double(i) / Double(totalFrames)
            let currentFreq = startFreq + (endFreq - startFreq) * t

            // Accumulate phase for smooth sweep
            phase += 2.0 * Double.pi * currentFreq / sampleRate
            var sample = amplitude * Float(sin(phase))

            // Fade envelope
            if i < fadeSamples {
                sample *= Float(i) / Float(fadeSamples)
            } else if i > Int(totalFrames) - fadeSamples {
                let remaining = Int(totalFrames) - i
                sample *= Float(remaining) / Float(fadeSamples)
            }

            channelData[i] = sample
        }

        return buffer
    }

    // MARK: - Playback

    /// Plays a PCM buffer using a dedicated AVAudioEngine with .ambient category
    /// so it mixes over the main .playAndRecord session without conflict.
    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        // Configure audio session as ambient + mix so we don't steal the main session
        let session = AVAudioSession.sharedInstance()
        let previousCategory = session.category
        let previousOptions = session.categoryOptions

        do {
            try session.setCategory(.ambient, options: .mixWithOthers)
        } catch {
            // If we can't set ambient, play anyway — worst case it's a brief glitch
        }

        // Create a fresh engine each time to avoid state issues
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)

        do {
            try engine.start()
        } catch {
            restoreAudioSession(category: previousCategory, options: previousOptions)
            return
        }

        // Schedule buffer and restore session when done
        playerNode.scheduleBuffer(buffer) {
            Task { @MainActor in
                engine.stop()
                self.restoreAudioSession(category: previousCategory, options: previousOptions)
            }
        }
        playerNode.play()
    }

    /// Restores the audio session to its previous category after tone playback.
    private func restoreAudioSession(category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) {
        do {
            try AVAudioSession.sharedInstance().setCategory(category, options: options)
        } catch {
            // Best effort — the main audio engine will reconfigure on next use
        }
    }
}
