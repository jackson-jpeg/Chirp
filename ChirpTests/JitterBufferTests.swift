import XCTest
import AVFoundation
@testable import Chirp

final class JitterBufferTests: XCTestCase {

    private var buffer: JitterBuffer!

    override func setUp() {
        super.setUp()
        // Use minimal initial depth (1 frame = 20ms) so tests don't need many pushes
        buffer = JitterBuffer(initialDepthMs: 20, maxDepthMs: 200)
    }

    override func tearDown() {
        buffer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a PCM buffer in the format JitterBuffer expects: Int16, 16kHz, mono, 320 samples.
    private func makePCMBuffer(sampleValue: Int16 = 1000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(Constants.Opus.sampleRate),
            channels: 1,
            interleaved: true
        )!
        let frameCount = AVAudioFrameCount(Constants.Opus.samplesPerFrame) // 320
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.int16ChannelData?[0] {
            for i in 0..<Int(frameCount) {
                channelData[i] = sampleValue
            }
        }
        return pcmBuffer
    }

    // MARK: - Basic push and pull

    func testPushAndPullReturnsData() {
        let pcm = makePCMBuffer()
        // Push enough to satisfy initial buffering depth (1 frame with 20ms init)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 1)

        let pulled = buffer.pull(frameCount: 1)
        XCTAssertNotNil(pulled, "Pull should return data after sufficient pushes")
    }

    func testPullWhenEmptyReturnsNil() {
        let pulled = buffer.pull(frameCount: 1)
        XCTAssertNil(pulled, "Pull on empty buffer should return nil")
    }

    // MARK: - Ordering

    func testPacketsReorderedBySequenceNumber() {
        let pcm1 = makePCMBuffer(sampleValue: 100)
        let pcm2 = makePCMBuffer(sampleValue: 200)
        let pcm3 = makePCMBuffer(sampleValue: 300)

        // Push out of order: 2, 0, 1
        buffer.push(pcmBuffer: pcm3, sequenceNumber: 2)
        buffer.push(pcmBuffer: pcm1, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm2, sequenceNumber: 1)

        // Pull should return data (3 frames pushed, 1 needed for buffering)
        let pull0 = buffer.pull(frameCount: 1)
        let pull1 = buffer.pull(frameCount: 1)
        let pull2 = buffer.pull(frameCount: 1)

        XCTAssertNotNil(pull0)
        XCTAssertNotNil(pull1)
        XCTAssertNotNil(pull2)
    }

    // MARK: - Buffer overflow trimming

    func testOverflowTrimsOldestPackets() {
        let pcm = makePCMBuffer()

        // Push many packets to trigger overflow trimming
        for seq in 0..<50 {
            buffer.push(pcmBuffer: pcm, sequenceNumber: UInt32(seq))
        }

        // Buffer should still be functional
        let pulled = buffer.pull(frameCount: 1)
        XCTAssertNotNil(pulled, "Buffer should still return data after overflow trimming")
    }

    // MARK: - Reset

    func testResetClearsBuffer() {
        let pcm = makePCMBuffer()
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 1)

        buffer.reset()

        XCTAssertNil(buffer.pull(frameCount: 1), "Pull after reset should return nil")
    }

    func testResetAllowsFreshSequenceNumbers() {
        let pcm = makePCMBuffer()
        buffer.push(pcmBuffer: pcm, sequenceNumber: 10)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 11)
        _ = buffer.pull(frameCount: 1)

        buffer.reset()

        // After reset, earlier sequence numbers should work
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 1)
        let pulled = buffer.pull(frameCount: 1)
        XCTAssertNotNil(pulled, "After reset, earlier sequence numbers should be accepted")
    }

    // MARK: - Sequence number wraparound

    func testSequenceNumberWraparoundAtMax() {
        let pcm = makePCMBuffer()

        // Push frames near UInt32.max
        let start = UInt32.max - 3
        for i: UInt32 in 0..<4 {
            buffer.push(pcmBuffer: pcm, sequenceNumber: start &+ i)
        }

        // Pull all of them so lastPulledSequence advances to UInt32.max
        for _ in 0..<4 {
            _ = buffer.pull(frameCount: 1)
        }

        // Now push frames starting at 0 (wrapped around)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 1)

        // The buffer should NOT drop seq=0 and seq=1 as "late"
        let pulled = buffer.pull(frameCount: 1)
        XCTAssertNotNil(pulled, "Wrapped-around sequence numbers starting at 0 should be accepted after UInt32.max")
        XCTAssertEqual(buffer.packetsDroppedLate, 0, "No packets should be dropped as late during wraparound")
    }

    func testLatePacketDetectionAcrossWraparound() {
        let pcm = makePCMBuffer()

        // Push frames near UInt32.max and pull them
        let start = UInt32.max - 3
        for i: UInt32 in 0..<4 {
            buffer.push(pcmBuffer: pcm, sequenceNumber: start &+ i)
        }
        for _ in 0..<4 {
            _ = buffer.pull(frameCount: 1)
        }
        // lastPulledSequence is now UInt32.max

        let droppedBefore = buffer.packetsDroppedLate

        // Push a packet that is genuinely late (behind the last pulled, even considering wraparound)
        // UInt32.max - 5 is behind UInt32.max, so it should be dropped
        buffer.push(pcmBuffer: pcm, sequenceNumber: UInt32.max - 5)
        XCTAssertEqual(
            buffer.packetsDroppedLate, droppedBefore + 1,
            "Packet behind lastPulled should be dropped as late even near wraparound boundary"
        )

        // But seq 0 (wrapped around, ahead) should NOT be dropped
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        XCTAssertEqual(
            buffer.packetsDroppedLate, droppedBefore + 1,
            "Wrapped-around seq 0 should NOT be dropped — it is ahead of UInt32.max"
        )
    }
}
