import Foundation

/// The three chirps a bird can have (`Bird.chirp`): Finch, Robin and Wren.
///
/// Made from a few lines of math rather than shipped recordings, so there is
/// nothing to license and every phone makes the same sound. Each is short
/// (under half a second) and sits in 2 to 5 kHz, where a phone speaker is loud
/// and a bird is believable.
///
/// Played when a friend starts talking (their chirp), as a preview in Make
/// your bird, and when a friend pings you.
public enum ChirpSound {
    public static let names = ["Finch", "Robin", "Wren"]
    public static let sampleRate = 44_100

    /// One note: a pitch glide from `from` to `to` Hz over `seconds`, with an
    /// optional vibrato, then `gap` seconds of silence.
    struct Note {
        var from: Double
        var to: Double
        var seconds: Double
        var vibratoHz: Double = 0
        var vibratoDepth: Double = 0
        var gap: Double = 0
    }

    static func notes(_ chirp: Int) -> [Note] {
        switch chirp {
        case 0: // Finch: two quick rising notes.
            return [Note(from: 3_200, to: 4_300, seconds: 0.07, gap: 0.045),
                    Note(from: 3_400, to: 4_600, seconds: 0.08)]
        case 1: // Robin: one warbled note that rises and falls back.
            return [Note(from: 2_500, to: 3_300, seconds: 0.11, vibratoHz: 28, vibratoDepth: 120),
                    Note(from: 3_300, to: 2_800, seconds: 0.12, vibratoHz: 28, vibratoDepth: 120)]
        default: // Wren: a fast falling trill of five.
            return (0..<5).map { i in
                let top = 4_700 - Double(i) * 150
                return Note(from: top, to: top - 500, seconds: 0.035, gap: i < 4 ? 0.022 : 0)
            }
        }
    }

    /// Mono samples in -1...1. An unknown chirp number plays Wren, the last one,
    /// as `Bird` keeps chirps in range anyway.
    public static func samples(_ chirp: Int, sampleRate: Int = sampleRate) -> [Float] {
        let rate = Double(sampleRate)
        var out: [Float] = []
        var phase = 0.0
        for note in notes(chirp) {
            let count = Int(note.seconds * rate)
            for i in 0..<count {
                let t = Double(i) / rate
                let progress = Double(i) / Double(max(1, count - 1))
                let vibrato = note.vibratoDepth * sin(2 * .pi * note.vibratoHz * t)
                let hz = note.from + (note.to - note.from) * progress + vibrato
                phase += 2 * .pi * hz / rate
                // A raised-sine envelope: no click at either end of the note.
                let envelope = sin(.pi * progress)
                // A little second harmonic makes it sound less like a test tone.
                let s = (sin(phase) + 0.25 * sin(2 * phase)) / 1.25
                out.append(Float(0.7 * envelope * s))
            }
            out += [Float](repeating: 0, count: Int(note.gap * rate))
        }
        return out
    }

    /// A 16-bit mono WAV file of the chirp, ready for `AVAudioPlayer(data:)`.
    public static func wav(_ chirp: Int, sampleRate: Int = sampleRate) -> Data {
        let pcm = samples(chirp, sampleRate: sampleRate).map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        let dataBytes = UInt32(pcm.count * 2)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for s in pcm { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
        return d
    }
}
