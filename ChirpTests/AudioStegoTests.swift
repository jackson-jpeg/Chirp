import XCTest
import CryptoKit
@testable import Chirp

final class AudioStegoTests: XCTestCase {

    private let testKey = SymmetricKey(size: .bits256)

    func testTimingScheduleProducesDelays() {
        let hidden = Data("test".utf8)
        var schedule = AudioStego.TimingSchedule(hidden: hidden, key: testKey)
        XCTAssertFalse(schedule.isComplete)

        var delays: [TimeInterval] = []
        while let delay = schedule.nextDelay() {
            delays.append(delay)
        }
        XCTAssertTrue(schedule.isComplete)
        XCTAssertGreaterThan(delays.count, 0)

        // All delays should be close to 19ms or 21ms
        for delay in delays {
            let diff = abs(delay - AudioStego.nominalInterval)
            XCTAssertEqual(diff, AudioStego.timingOffset, accuracy: 0.0001)
        }
    }

    func testTimingScheduleProgress() {
        let hidden = Data("x".utf8)
        var schedule = AudioStego.TimingSchedule(hidden: hidden, key: testKey)
        XCTAssertEqual(schedule.progress, 0, accuracy: 0.01)
        _ = schedule.nextDelay()
        XCTAssertGreaterThan(schedule.progress, 0)
    }

    func testEstimatedDuration() {
        let duration = AudioStego.estimatedDuration(hiddenBytes: 10)
        XCTAssertGreaterThan(duration, 0)
        // 10 bytes + 31 overhead = 41 bytes = 328 bits + 16 header = 344 bits x 20ms = ~6.88 seconds
        XCTAssertGreaterThan(duration, 5.0)
    }

    func testCovertBandwidth() {
        XCTAssertEqual(AudioStego.covertBandwidth, 6.25, accuracy: 0.01)
    }

    func testDecoderReset() {
        let decoder = AudioStego.TimingDecoder(key: testKey)
        decoder.recordPacket()
        decoder.recordPacket()
        decoder.reset()
        // After reset, decode should return nil (no data)
        XCTAssertNil(decoder.decode())
    }
}
