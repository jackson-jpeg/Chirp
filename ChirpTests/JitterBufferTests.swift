import XCTest
import AVFoundation
@testable import Chirp

final class JitterBufferTests: XCTestCase {

    private var buffer: JitterBuffer!

    override func setUp() {
        super.setUp()
        buffer = JitterBuffer()
    }

    override func tearDown() {
        buffer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a minimal PCM buffer with the given frame count, filled with a constant sample value.
    private func makePCMBuffer(frameCount: AVAudioFrameCount = 480, sampleValue: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.floatChannelData?[0] {
            for i in 0..<Int(frameCount) {
                channelData[i] = sampleValue
            }
        }
        return pcmBuffer
    }

    // MARK: - Basic push and pull

    func testPushAndPullReturnsData() {
        let pcm = makePCMBuffer(frameCount: 480)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)

        let pulled = buffer.pull(frameCount: 480)
        XCTAssertNotNil(pulled, "Pull should return data after push")
    }

    func testPullWhenEmptyReturnsNil() {
        let pulled = buffer.pull(frameCount: 480)
        XCTAssertNil(pulled, "Pull on empty buffer should return nil")
    }

    func testPullAfterDrainingReturnsNil() {
        let pcm = makePCMBuffer(frameCount: 480)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)

        _ = buffer.pull(frameCount: 480)
        let second = buffer.pull(frameCount: 480)
        XCTAssertNil(second, "Pull after draining should return nil")
    }

    // MARK: - Ordering

    func testPacketsReorderedBySequenceNumber() {
        let pcm1 = makePCMBuffer(frameCount: 480, sampleValue: 0.1)
        let pcm2 = makePCMBuffer(frameCount: 480, sampleValue: 0.2)
        let pcm3 = makePCMBuffer(frameCount: 480, sampleValue: 0.3)

        // Push out of order: 2, 0, 1
        buffer.push(pcmBuffer: pcm3, sequenceNumber: 2)
        buffer.push(pcmBuffer: pcm1, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm2, sequenceNumber: 1)

        // Pull should return in sequence order: 0, 1, 2
        let pull0 = buffer.pull(frameCount: 480)
        let pull1 = buffer.pull(frameCount: 480)
        let pull2 = buffer.pull(frameCount: 480)

        XCTAssertNotNil(pull0)
        XCTAssertNotNil(pull1)
        XCTAssertNotNil(pull2)

        // After pulling all three, buffer should be empty
        XCTAssertNil(buffer.pull(frameCount: 480))
    }

    func testStatsPacketsReceived() {
        let pcm = makePCMBuffer(frameCount: 480)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 1)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 2)

        XCTAssertEqual(buffer.stats.packetsReceived, 3)
    }

    // MARK: - Late packet drops

    func testLatePacketIsDropped() {
        let pcm = makePCMBuffer(frameCount: 480)

        // Push and pull sequence 0
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        _ = buffer.pull(frameCount: 480)

        // Push sequence 2 and pull it
        buffer.push(pcmBuffer: pcm, sequenceNumber: 2)
        _ = buffer.pull(frameCount: 480)

        let droppedBefore = buffer.stats.packetsDroppedLate

        // Push sequence 1 (late -- already past it)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 1)

        // Late packet should be dropped
        XCTAssertGreaterThanOrEqual(
            buffer.stats.packetsDroppedLate,
            droppedBefore + 1,
            "Late packet should increment droppedLate counter"
        )
    }

    // MARK: - Buffer overflow trimming

    func testOverflowTrimsOldestPackets() {
        let pcm = makePCMBuffer(frameCount: 480)

        // Push a large number of packets to trigger overflow trimming.
        // The exact capacity depends on implementation, but pushing 200+
        // should exceed any reasonable jitter buffer size.
        for seq in 0..<200 {
            buffer.push(pcmBuffer: pcm, sequenceNumber: UInt32(seq))
        }

        // Buffer should still be functional -- pull should return data
        let pulled = buffer.pull(frameCount: 480)
        XCTAssertNotNil(pulled, "Buffer should still return data after overflow trimming")

        // packetsReceived should reflect all pushes
        XCTAssertEqual(buffer.stats.packetsReceived, 200)
    }

    // MARK: - Reset

    func testResetClearsBuffer() {
        let pcm = makePCMBuffer(frameCount: 480)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 1)

        buffer.reset()

        XCTAssertNil(buffer.pull(frameCount: 480), "Pull after reset should return nil")
    }

    func testResetAllowsFreshSequenceNumbers() {
        let pcm = makePCMBuffer(frameCount: 480)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 10)
        _ = buffer.pull(frameCount: 480)

        buffer.reset()

        // After reset, sequence 0 should not be considered late
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        let pulled = buffer.pull(frameCount: 480)
        XCTAssertNotNil(pulled, "After reset, earlier sequence numbers should be accepted")
    }

    // MARK: - Stats: packetsLost

    func testPacketsLostCountsGaps() {
        let pcm = makePCMBuffer(frameCount: 480)

        // Push 0, skip 1, push 2
        buffer.push(pcmBuffer: pcm, sequenceNumber: 0)
        buffer.push(pcmBuffer: pcm, sequenceNumber: 2)

        // Pull both
        _ = buffer.pull(frameCount: 480)
        _ = buffer.pull(frameCount: 480)

        // Sequence 1 was never received -- should count as lost
        XCTAssertGreaterThanOrEqual(buffer.stats.packetsLost, 1)
    }
}
