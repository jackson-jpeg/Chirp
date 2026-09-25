import SwiftUI
import UIKit

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
        /// Depth reached before playout starts (and again after an underrun).
        /// Must exceed one capture chunk: the mic tap delivers ~85–100ms of
        /// audio at a time (4096 frames @ 48kHz), so Opus frames leave the
        /// sender in bursts of 4–5, not one per 20ms. A gate smaller than a
        /// burst (the old 40ms) drained dry between bursts every cycle and
        /// played a phase-discontinuous concealment frame each time — audible
        /// as periodic glitching during sustained PTT, and caught by the
        /// loopback tone-correlation test.
        static let initialDepthMs: Int = 140
        /// Ceiling before the oldest frames are trimmed. Must leave room for
        /// a full burst to land on top of a buffer sitting at the gate depth
        /// (7 + 5 frames), or the trim itself starts discarding real audio.
        static let maxDepthMs: Int = 300
    }

    enum Heartbeat {
        static let intervalSeconds: TimeInterval = 5.0
    }

    enum TextMessages {
        /// Maximum messages retained per channel, in memory and on disk.
        ///
        /// Single source of truth: `TextMessageService` enforces it and
        /// `ChirpTests/TextMessageServiceTests.swift` asserts against it. The
        /// number was previously held independently in both places, which let
        /// them drift — the service trimmed to 200 while the tests expected 500 —
        /// with nothing to catch it, because the test target had never been built.
        static let maxPerChannel = 200
    }

    /// The "Sky classic" palette, taken from the app icon: a daytime sky
    /// (#4AACEA → #9FD9F7) with white clouds, sunny birds (#FFC93A body,
    /// #EF961C wing, #FF7A2E beak) and navy ink (#1F2D52).
    ///
    /// Every token is adaptive: `day` in Light Mode, `night` in Dark Mode. The
    /// names predate the sky theme (the app was once dark-only slate + amber),
    /// so read them as ROLES, not hues:
    ///
    /// - `slate900` / `backgroundPrimary` — the page. Night navy / pale sky.
    /// - `slate800` / `cardBackground`    — a raised card. Night card / white.
    /// - `slate700`                       — inactive fills and hairlines.
    /// - `slate600`, `slate500`, `slate400` — tertiary → secondary text.
    /// - `textPrimary` / `ink`            — the main foreground. White / navy.
    /// - `surfaceGlass`                   — a translucent card on the page:
    ///   a white card by day. Too faint for a divider — use `surfaceBorder`.
    ///
    /// `amber` is a FILL (the PTT button, selected tabs, badges); put
    /// `onAmber` text on it. For amber TEXT or icons on the page use
    /// `amberInk`, which darkens by day so it stays readable on white.
    /// Every text pairing here clears WCAG AA (4.5:1) in both modes, measured.
    enum Colors {
        // Brand — straight from the icon, the same in both modes
        static let sky = Color(hex: 0x4AACEA)
        static let skyLight = Color(hex: 0x9FD9F7)
        static let cloud = Color(hex: 0xCFE8F7)
        static let navy = Color(hex: 0x1F2D52)
        static let sun = Color(hex: 0xFFC93A)
        static let wing = Color(hex: 0xEF961C)
        static let beak = Color(hex: 0xFF7A2E)

        // Primary accent (a fill — see `amberInk` for text)
        static let amber = Color(day: 0xFFBF2E, night: 0xFFC93A)
        static let amberLight = Color(day: 0xFFE08A, night: 0xFFD866)
        static let amberDark = Color(day: 0xC96F00, night: 0xEF961C)
        /// Accent for text and icons drawn on the page or a card.
        static let amberInk = Color(day: 0xA85800, night: 0xFFC93A)
        /// Text and icons drawn on an `amber` fill.
        static let onAmber = Color(hex: 0x1F2D52)

        // Status
        static let electricGreen = Color(day: 0x1A8440, night: 0x34D27A)
        static let hotRed = Color(day: 0xD7281C, night: 0xFF5A4E)
        static let emergencyRed = Color(day: 0xB8140C, night: 0xE0241A)

        // Role palette (see the table above)
        static let slate50 = Color(day: 0x1F2D52, night: 0xF5F9FF)
        static let slate400 = Color(day: 0x4A5D82, night: 0x9FB0D0)
        static let slate500 = Color(day: 0x5F7394, night: 0x7A8BAB)
        static let slate600 = Color(day: 0x7B8CAB, night: 0x5A6B8E)
        static let slate700 = Color(day: 0xC9DEEE, night: 0x2B3B66)
        static let slate800 = Color(day: 0xFFFFFF, night: 0x16213F)
        static let slate900 = Color(day: 0xEEF7FD, night: 0x0D1630)
        /// Sky blue for buttons and active states. White text on it passes AA.
        static let blue500 = Color(day: 0x1877C2, night: 0x3A9AE0)
        static let blue600 = Color(day: 0x13639F, night: 0x2A84CC)

        // Backgrounds
        static let backgroundPrimary = Color(day: 0xEEF7FD, night: 0x0D1630)
        static let backgroundSecondary = Color(day: 0xEEF7FD, night: 0x0D1630)
        static let backgroundTertiary = Color(day: 0xFFFFFF, night: 0x16213F)
        static let backgroundDeep = Color(day: 0xDCEFFA, night: 0x070D1F)
        static let cardBackground = Color(day: 0xFFFFFF, night: 0x16213F)

        /// The main foreground: white at night, navy by day. Use it wherever
        /// the old code said `.white` for text or hairlines on the page, e.g.
        /// `ink.opacity(0.06)` for a divider.
        static let ink = Color(day: 0x1F2D52, night: 0xFFFFFF)

        // Surface
        static let surfaceGlass = Color(day: 0xFFFFFF, night: 0xFFFFFF, dayOpacity: 0.82, nightOpacity: 0.08)
        static let surfaceBorder = Color(day: 0x1F2D52, night: 0xFFFFFF, dayOpacity: 0.12, nightOpacity: 0.10)
        static let surfaceHover = Color(day: 0x1F2D52, night: 0xFFFFFF, dayOpacity: 0.08, nightOpacity: 0.15)

        // Text
        static let textPrimary = Color(day: 0x1F2D52, night: 0xFFFFFF)
        static let textSecondary = Color(day: 0x1F2D52, night: 0xFFFFFF, dayOpacity: 0.72, nightOpacity: 0.6)
        static let textTertiary = Color(day: 0x1F2D52, night: 0xFFFFFF, dayOpacity: 0.5, nightOpacity: 0.35)

        // Mesh
        static let meshHealthGood = electricGreen
        static let meshHealthFair = Color(day: 0xE08A00, night: 0xFFC93A)
        static let meshHealthPoor = hotRed

        // Frosted Glass Tints — brighter for material refraction
        static let glassAmber = amber.opacity(0.20)
        static let glassAmberBorder = amber.opacity(0.50)
        static let glassAmberGlow = amber.opacity(0.40)

        static let glassGreen = electricGreen.opacity(0.18)
        static let glassGreenBorder = electricGreen.opacity(0.45)
        static let glassGreenGlow = electricGreen.opacity(0.35)

        static let glassRed = hotRed.opacity(0.20)
        static let glassRedBorder = hotRed.opacity(0.50)
        static let glassRedGlow = hotRed.opacity(0.40)
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
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension Color {
    /// An appearance-adaptive color: `day` in Light Mode, `night` in Dark Mode.
    init(day: UInt, night: UInt, dayOpacity: Double = 1.0, nightOpacity: Double = 1.0) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: night, alpha: nightOpacity)
                : UIColor(hex: day, alpha: dayOpacity)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt, alpha: Double) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(alpha)
        )
    }
}
