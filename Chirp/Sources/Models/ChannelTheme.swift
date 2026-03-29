import SwiftUI

struct ChannelTheme: Codable, Sendable, Equatable {
    let primaryColor: UInt    // hex color
    let icon: String          // SF Symbol name
    let emoji: String         // channel emoji

    // Preset themes
    static let squad = ChannelTheme(primaryColor: 0xFFB800, icon: "shield.fill", emoji: "⚔️")
    static let family = ChannelTheme(primaryColor: 0xFF6B9D, icon: "heart.fill", emoji: "❤️")
    static let emergency = ChannelTheme(primaryColor: 0xFF3B30, icon: "exclamationmark.triangle.fill", emoji: "🚨")
    static let adventure = ChannelTheme(primaryColor: 0x30D158, icon: "mountain.2.fill", emoji: "🏔️")
    static let concert = ChannelTheme(primaryColor: 0xBF5AF2, icon: "music.note", emoji: "🎵")
    static let sports = ChannelTheme(primaryColor: 0x0A84FF, icon: "sportscourt.fill", emoji: "🏟️")
    static let work = ChannelTheme(primaryColor: 0x64D2FF, icon: "briefcase.fill", emoji: "💼")
    static let gaming = ChannelTheme(primaryColor: 0x30D158, icon: "gamecontroller.fill", emoji: "🎮")

    static let allPresets: [ChannelTheme] = [squad, family, emergency, adventure, concert, sports, work, gaming]

    var color: Color { Color(hex: primaryColor) }
}
