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
        // Primary
        static let amber = Color(hex: 0xFFB800)
        static let amberLight = Color(hex: 0xFFD060)
        static let amberDark = Color(hex: 0xCC9300)

        // Status
        static let electricGreen = Color(hex: 0x30D158)
        static let hotRed = Color(hex: 0xFF3B30)
        static let emergencyRed = Color(hex: 0xCC0000)

        // Modern palette
        static let slate50 = Color(hex: 0xF8FAFC)
        static let slate400 = Color(hex: 0x94A3B8)
        static let slate500 = Color(hex: 0x64748B)
        static let slate600 = Color(hex: 0x475569)
        static let slate700 = Color(hex: 0x334155)
        static let slate800 = Color(hex: 0x1E293B)
        static let slate900 = Color(hex: 0x0F172A)
        static let blue500 = Color(hex: 0x3B82F6)
        static let blue600 = Color(hex: 0x2563EB)

        // Backgrounds
        static let backgroundPrimary = Color(hex: 0x0F172A)
        static let backgroundSecondary = Color(hex: 0x0F172A)
        static let backgroundTertiary = Color(hex: 0x1E293B)
        static let cardBackground = Color(hex: 0x1E293B)

        // Surface
        static let surfaceGlass = Color.white.opacity(0.08)
        static let surfaceBorder = Color.white.opacity(0.10)
        static let surfaceHover = Color.white.opacity(0.15)

        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)
        static let textTertiary = Color.white.opacity(0.35)

        // Mesh
        static let meshHealthGood = Color(hex: 0x30D158)
        static let meshHealthFair = Color(hex: 0xFFB800)
        static let meshHealthPoor = Color(hex: 0xFF3B30)

        // Frosted Glass Tints — brighter for material refraction
        static let glassAmber = Color(hex: 0xFFB800).opacity(0.20)
        static let glassAmberBorder = Color(hex: 0xFFB800).opacity(0.50)
        static let glassAmberGlow = Color(hex: 0xFFB800).opacity(0.40)

        static let glassGreen = Color(hex: 0x30D158).opacity(0.18)
        static let glassGreenBorder = Color(hex: 0x30D158).opacity(0.45)
        static let glassGreenGlow = Color(hex: 0x30D158).opacity(0.35)

        static let glassRed = Color(hex: 0xFF3B30).opacity(0.20)
        static let glassRedBorder = Color(hex: 0xFF3B30).opacity(0.50)
        static let glassRedGlow = Color(hex: 0xFF3B30).opacity(0.40)
    }

    enum Typography {
        static let heroTitle = Font.system(size: 34, weight: .heavy, design: .rounded)
        static let sectionTitle = Font.system(size: 22, weight: .bold, design: .rounded)
        static let cardTitle = Font.system(size: 18, weight: .bold, design: .rounded)
        static let body = Font.system(size: 16, weight: .medium)
        static let caption = Font.system(size: 13, weight: .medium)
        static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
        static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let badge = Font.system(size: 10, weight: .bold, design: .rounded)
        static let monoDisplay = Font.system(size: 20, weight: .black, design: .monospaced)
        static let monoLarge = Font.system(size: 16, weight: .bold, design: .monospaced)
        static let monoStatus = Font.system(size: 14, weight: .bold, design: .monospaced)
        static let headline = Font.system(size: 22, weight: .heavy, design: .rounded)
    }

    enum Layout {
        static let cornerRadius: CGFloat = 18
        static let cardCornerRadius: CGFloat = 22
        static let buttonCornerRadius: CGFloat = 14
        static let horizontalPadding: CGFloat = 20
        static let cardPadding: CGFloat = 18
        static let spacing: CGFloat = 16
        static let smallSpacing: CGFloat = 8
        static let pttButtonSize: CGFloat = 160
        static let glassCornerRadius: CGFloat = 14
        static let glassBorderWidth: CGFloat = 1.5
    }

    enum Animations {
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.8
        static let quickFade: Double = 0.2
    }

    enum CICADA {
        /// Version byte prepended to encrypted hidden payload.
        static let version: UInt8 = 0x01
        /// HKDF salt for deriving CICADA keys from channel keys.
        static let keySalt = "CICADA-v1"
        /// Zero-width space — represents bit 0.
        static let bit0: Character = "\u{200B}"
        /// Zero-width non-joiner — represents bit 1.
        static let bit1: Character = "\u{200C}"
        /// Set of invisible characters used for stego.
        static let invisibleChars: Set<Character> = ["\u{200B}", "\u{200C}"]
        /// Crypto overhead: 1 version + 2 length + 12 nonce + 16 tag = 31 bytes
        static let cryptoOverhead = 31
        /// Bits encoded per inter-character position (2 invisible chars = 2 bits).
        static let bitsPerPosition = 2
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
