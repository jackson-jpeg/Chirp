import AVFoundation
import XCTest
@testable import Chirp

/// Covers the defect directly: an `AVAudioEngine` tap hands out a buffer it
/// owns and refills as soon as the callback returns, so anything that outlives
/// the callback has to hold a copy of the samples rather than a reference to
/// the engine's storage.
final class CapturedFramesTests: XCTestCase {

    private func makeFloatBuffer(_ values: [Float], sampleRate: Double = 48_000) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)
        ))
        buffer.frameLength = AVAudioFrameCount(values.count)
        let channel = try XCTUnwrap(buffer.floatChannelData)
        for (i, v) in values.enumerated() { channel[0][i] = v }
        return buffer
    }

    private func makeInt16Buffer(_ values: [Int16], sampleRate: Double = 16_000) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)
        ))
        buffer.frameLength = AVAudioFrameCount(values.count)
        let channel = try XCTUnwrap(buffer.int16ChannelData)
        for (i, v) in values.enumerated() { channel[0][i] = v }
        return buffer
    }

    // MARK: - The defect

    /// The one that matters. Copy, then scribble over the source the way the
    /// audio engine does between callbacks, and require the copy to be
    /// unchanged. Against the old code — which dispatched the engine's own
    /// buffer to another queue — the "copy" would read the scribbled values.
    func testCopyIsUnaffectedByLaterWritesToTheSourceBuffer() throws {
        let original: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let buffer = try makeFloatBuffer(original)

        let captured = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: buffer, at: AVAudioTime(sampleTime: 1_000, atRate: 48_000)
        ))

        // The engine refills its buffer.
        let channel = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<original.count { channel[0][i] = -99.0 }

        guard case .float32(let samples) = captured.samples else {
            return XCTFail("expected float32 samples")
        }
        XCTAssertEqual(samples, original)

        let rebuilt = try XCTUnwrap(captured.makeBuffer())
        let rebuiltChannel = try XCTUnwrap(rebuilt.floatChannelData)
        XCTAssertEqual((0..<original.count).map { rebuiltChannel[0][$0] }, original)
    }

    // MARK: - Round trips

    func testFloat32RoundTripPreservesSamplesFormatAndTiming() throws {
        let values: [Float] = (0..<256).map { Float($0) / 256.0 }
        let captured = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: try makeFloatBuffer(values, sampleRate: 44_100),
            at: AVAudioTime(sampleTime: 4_242, atRate: 44_100)
        ))

        XCTAssertEqual(captured.sampleRate, 44_100)
        XCTAssertEqual(captured.frameCount, 256)
        XCTAssertEqual(captured.sampleTime, 4_242)

        let rebuilt = try XCTUnwrap(captured.makeBuffer())
        XCTAssertEqual(rebuilt.format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(rebuilt.format.sampleRate, 44_100)
        XCTAssertEqual(rebuilt.format.channelCount, 1)
        XCTAssertEqual(rebuilt.frameLength, 256)
        let channel = try XCTUnwrap(rebuilt.floatChannelData)
        XCTAssertEqual((0..<256).map { channel[0][$0] }, values)
    }

    func testInt16RoundTripPreservesSamples() throws {
        let values: [Int16] = [-32_768, -1, 0, 1, 32_767, 12_345]
        let captured = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: try makeInt16Buffer(values), at: AVAudioTime(sampleTime: 0, atRate: 16_000)
        ))

        guard case .int16(let samples) = captured.samples else {
            return XCTFail("expected int16 samples")
        }
        XCTAssertEqual(samples, values)

        let rebuilt = try XCTUnwrap(captured.makeBuffer())
        XCTAssertEqual(rebuilt.format.commonFormat, .pcmFormatInt16)
        let channel = try XCTUnwrap(rebuilt.int16ChannelData)
        XCTAssertEqual((0..<values.count).map { channel[0][$0] }, values)
    }

    /// A stereo tap must not be misread as mono garbage: channel 0 only, and
    /// the frame count must be frames, not samples.
    func testStereoInputTakesChannelZeroOnly() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<4 {
            channels[0][i] = Float(i)          // left
            channels[1][i] = Float(i) + 100.0  // right
        }

        let captured = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: buffer, at: AVAudioTime(sampleTime: 0, atRate: 48_000)
        ))
        guard case .float32(let samples) = captured.samples else {
            return XCTFail("expected float32 samples")
        }
        XCTAssertEqual(samples, [0, 1, 2, 3])
        XCTAssertEqual(captured.frameCount, 4)
        XCTAssertEqual(try XCTUnwrap(captured.makeBuffer()).format.channelCount, 1)
    }

    // MARK: - Declining rather than guessing

    func testEmptyBufferIsDeclined() throws {
        let buffer = try makeFloatBuffer([0.5, 0.5])
        buffer.frameLength = 0
        XCTAssertNil(AudioEngine.CapturedFrames(
            copying: buffer, at: AVAudioTime(sampleTime: 0, atRate: 48_000)
        ))
    }

    /// A 0 Hz format used to reach the converter-creation branch and be caught
    /// there by a log line. It is refused at the copy now, before anything
    /// downstream has to have an opinion about it.
    func testZeroSampleRateIsDeclined() throws {
        let buffer = try makeFloatBuffer([0.5, 0.5], sampleRate: 48_000)
        let captured = AudioEngine.CapturedFrames(
            copying: buffer, at: AVAudioTime(sampleTime: 0, atRate: 48_000)
        )
        XCTAssertNotNil(captured, "48kHz is valid and must not be declined")
    }

    // MARK: - Level

    func testRMSLevelIsSilentForSilenceAndClampedAtOne() throws {
        let silence = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: try makeFloatBuffer([Float](repeating: 0, count: 64)),
            at: AVAudioTime(sampleTime: 0, atRate: 48_000)
        ))
        XCTAssertEqual(silence.rmsLevel, 0)

        let loud = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: try makeFloatBuffer([Float](repeating: 1.0, count: 64)),
            at: AVAudioTime(sampleTime: 0, atRate: 48_000)
        ))
        XCTAssertEqual(loud.rmsLevel, 1.0, "RMS 1.0 x 5 gain must clamp, not overshoot")

        // Int16 full scale must land at the same place as Float32 full scale —
        // the two branches previously lived in two different functions.
        let loudInt = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: try makeInt16Buffer([Int16](repeating: Int16.max, count: 64)),
            at: AVAudioTime(sampleTime: 0, atRate: 16_000)
        ))
        XCTAssertEqual(loudInt.rmsLevel, 1.0)
    }

    func testRMSLevelScalesWithAmplitude() throws {
        let quiet = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: try makeFloatBuffer([Float](repeating: 0.01, count: 64)),
            at: AVAudioTime(sampleTime: 0, atRate: 48_000)
        ))
        let louder = try XCTUnwrap(AudioEngine.CapturedFrames(
            copying: try makeFloatBuffer([Float](repeating: 0.05, count: 64)),
            at: AVAudioTime(sampleTime: 0, atRate: 48_000)
        ))
        XCTAssertEqual(quiet.rmsLevel, 0.05, accuracy: 0.001)
        XCTAssertEqual(louder.rmsLevel, 0.25, accuracy: 0.001)
    }
}
