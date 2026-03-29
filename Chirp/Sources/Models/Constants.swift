import SwiftUI

enum Constants {
    static let subsystem = "com.chirpchirp.app"
    static let serviceName = "_chirp-ptt._udp"

    enum Opus {
        static let sampleRate: Double = 16_000
        static let channels: UInt32 = 1
        static let frameDuration: Double = 0.020
        static let bitrate: Int = 24_000
        static let samplesPerFrame: Int = 320
    }

    enum JitterBuffer {
        static let initialDepthMs: Int = 40
        static let maxDepthMs: Int = 200
    }

    enum Heartbeat {
        static let intervalSeconds: TimeInterval = 5.0
    }

    enum Colors {
        static let amber = Color(hex: 0xFFB800)
        static let hotRed = Color(hex: 0xFF3B30)
        static let electricGreen = Color(hex: 0x30D158)
        static let emergencyRed = Color(hex: 0xCC0000)
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
