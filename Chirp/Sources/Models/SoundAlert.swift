import Foundation

/// A detected emergency sound shared over the mesh.
struct SoundAlert: Codable, Sendable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let soundClass: SoundClass
    let confidence: Double
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

    enum SoundClass: String, Codable, Sendable, CaseIterable {
        case gunshot
        case scream
        case glassBreaking = "glass_breaking"
        case fireAlarm = "fire_alarm"
        case siren
        case explosion
        case smokeDetector = "smoke_detector"

        var displayName: String {
            switch self {
            case .gunshot: "Gunshot"
            case .scream: "Scream"
            case .glassBreaking: "Glass Breaking"
            case .fireAlarm: "Fire Alarm"
            case .siren: "Siren"
            case .explosion: "Explosion"
            case .smokeDetector: "Smoke Detector"
            }
        }

        var icon: String {
            switch self {
            case .gunshot: "burst.fill"
            case .scream: "waveform.path"
            case .glassBreaking: "bolt.trianglebadge.exclamationmark.fill"
            case .fireAlarm: "flame.fill"
            case .siren: "light.beacon.max.fill"
            case .explosion: "burst.fill"
            case .smokeDetector: "smoke.fill"
            }
        }
    }

    /// ASCII "SND!" -- 0x53 0x4E 0x44 0x21
    static let magicPrefix: [UInt8] = [0x53, 0x4E, 0x44, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> SoundAlert? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else { return nil }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(SoundAlert.self, from: Data(json))
    }
}
