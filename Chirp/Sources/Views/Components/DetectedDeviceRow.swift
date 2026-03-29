import SwiftUI

/// Reusable row component displaying a single ``BLEDevice`` in the room scanner.
struct DetectedDeviceRow: View {
    let device: BLEDevice

    var body: some View {
        HStack(spacing: 14) {
            // Category icon
            Image(systemName: categoryIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(threatColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(threatColor.opacity(0.15))
                )

            // Device info
            VStack(alignment: .leading, spacing: 3) {
                Text(device.manufacturerName ?? "Unknown Device")
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .lineLimit(1)

                if let name = device.name {
                    Text(name)
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .lineLimit(1)
                }

                Text(timeLabel)
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()

            // Signal strength + threat badge
            VStack(alignment: .trailing, spacing: 6) {
                SignalStrengthIndicator(level: signalLevel)

                Text(device.threatLevel.label)
                    .font(Constants.Typography.badge)
                    .foregroundStyle(threatTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(threatColor.opacity(0.2))
                    )
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Constants.Layout.cardPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.manufacturerName ?? "Unknown") device, \(device.threatLevel.label) threat, signal \(signalLevel) of 4")
    }

    // MARK: - Helpers

    /// Map RSSI to 0-4 signal bars.
    private var signalLevel: Int {
        let rssi = device.rssi
        if rssi >= -50 { return 4 }      // Excellent
        if rssi >= -65 { return 3 }      // Good
        if rssi >= -80 { return 2 }      // Fair
        if rssi >= -95 { return 1 }      // Weak
        return 0                          // No signal
    }

    private var categoryIcon: String {
        switch device.category {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .computer: return "laptopcomputer"
        case .wearable: return "applewatch"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker"
        case .tracker: return "location.circle"
        case .camera: return "video.fill"
        case .tv: return "tv"
        case .iot: return "sensor"
        case .infrastructure: return "wifi.router"
        case .unknown: return "questionmark.circle"
        }
    }

    private var threatColor: Color {
        switch device.threatLevel {
        case .none: return Constants.Colors.electricGreen
        case .low: return Constants.Colors.textSecondary
        case .medium: return Constants.Colors.amber
        case .high: return Constants.Colors.hotRed
        }
    }

    private var threatTextColor: Color {
        switch device.threatLevel {
        case .none: return Constants.Colors.electricGreen
        case .low: return Constants.Colors.textSecondary
        case .medium: return Constants.Colors.amber
        case .high: return Constants.Colors.hotRed
        }
    }

    private var timeLabel: String {
        let elapsed = Date().timeIntervalSince(device.firstSeen)
        if elapsed < 60 {
            return "seen \(Int(elapsed))s ago"
        } else {
            return "seen \(Int(elapsed / 60))m ago"
        }
    }
}
