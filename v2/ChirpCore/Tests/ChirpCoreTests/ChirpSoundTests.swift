import Foundation
import Testing
@testable import ChirpCore

@Suite struct ChirpSoundTests {
    @Test func oneSoundPerChirpABirdCanHave() {
        #expect(ChirpSound.names.count == Int(Bird.chirpCount))
    }

    @Test func eachChirpIsShortAudibleAndDifferent() {
        let all = (0..<Int(Bird.chirpCount)).map { ChirpSound.samples($0) }
        for s in all {
            let seconds = Double(s.count) / Double(ChirpSound.sampleRate)
            #expect(seconds > 0.1 && seconds < 0.5)
            #expect((s.map { abs($0) }.max() ?? 0) > 0.3)
            #expect(s.allSatisfy { $0 >= -1 && $0 <= 1 })
        }
        #expect(all[0] != all[1] && all[1] != all[2] && all[0] != all[2])
    }

    @Test func noClickAtEitherEnd() {
        for c in 0..<Int(Bird.chirpCount) {
            let s = ChirpSound.samples(c)
            #expect(abs(s.first ?? 1) < 0.01)
            #expect(abs(s.last ?? 1) < 0.01)
        }
    }

    @Test func theWavHeaderMatchesTheSamples() {
        let wav = ChirpSound.wav(1)
        let count = ChirpSound.samples(1).count
        #expect(wav.count == 44 + count * 2)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
        let dataSize = wav[40..<44].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        #expect(dataSize == UInt32(count * 2))
    }
}
