import AVFoundation

/// One microphone tap's samples, copied out of the engine's storage.
///
/// Carried over from 1.0 (the render-thread copy, audit section 7): the
/// engine refills the buffer it hands a tap the moment the callback returns,
/// so anything that outlives the callback copies. Plain numbers, so it is
/// Sendable by construction. Channel 0 only (every input here is mono).
struct CapturedFrames: Sendable {
    enum Samples: Sendable {
        case float32([Float])
        case int16([Int16])
    }

    let samples: Samples
    let sampleRate: Double
    let frameCount: AVAudioFrameCount

    init?(copying buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        guard frames > 0, buffer.format.sampleRate > 0 else { return nil }
        if let ch = buffer.floatChannelData {
            samples = .float32(Array(UnsafeBufferPointer(start: ch[0], count: frames)))
        } else if let ch = buffer.int16ChannelData {
            samples = .int16(Array(UnsafeBufferPointer(start: ch[0], count: frames)))
        } else {
            return nil
        }
        sampleRate = buffer.format.sampleRate
        frameCount = buffer.frameLength
    }

    /// A mono buffer owned by the caller.
    func makeBuffer() -> AVAudioPCMBuffer? {
        let common: AVAudioCommonFormat
        switch samples {
        case .float32: common = .pcmFormatFloat32
        case .int16: common = .pcmFormatInt16
        }
        guard let format = AVAudioFormat(commonFormat: common, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        switch samples {
        case .float32(let v):
            guard let dest = buffer.floatChannelData else { return nil }
            v.withUnsafeBufferPointer { dest[0].update(from: $0.baseAddress!, count: v.count) }
        case .int16(let v):
            guard let dest = buffer.int16ChannelData else { return nil }
            v.withUnsafeBufferPointer { dest[0].update(from: $0.baseAddress!, count: v.count) }
        }
        return buffer
    }

    #if DEBUG
    /// `-ChirpSineMic YES`: the same timing, samples replaced by a pulsed
    /// 440 Hz sine (200 ms on, 100 ms off), phase from the absolute sample
    /// position. The tap, converter and encoder still run for real, so a far
    /// end hearing this tone proves capture to mesh without trusting the
    /// simulator's microphone.
    init(pulsedSineReplacing original: CapturedFrames, startingAt position: Int64) {
        let rate = original.sampleRate
        var values = [Float](repeating: 0, count: Int(original.frameCount))
        for i in values.indices {
            let n = Double(position + Int64(i))
            guard (n / rate).truncatingRemainder(dividingBy: 0.3) < 0.2 else { continue }
            values[i] = 0.4 * Float(sin(2 * .pi * 440 * n / rate))
        }
        samples = .float32(values)
        sampleRate = rate
        frameCount = original.frameCount
    }
    #endif

    /// 0...1, for the talk button's level.
    var level: Float {
        let squares: Float, count: Int
        switch samples {
        case .float32(let v): count = v.count; squares = v.reduce(0) { $0 + $1 * $1 }
        case .int16(let v):
            count = v.count
            squares = v.reduce(0) { let x = Float($1) / Float(Int16.max); return $0 + x * x }
        }
        return count == 0 ? 0 : min(1, (squares / Float(count)).squareRoot() * 5)
    }
}
