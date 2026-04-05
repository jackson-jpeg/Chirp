import Foundation

enum CallsignGenerator {
    private static let adjectives = [
        "Phoenix", "Echo", "Shadow", "Falcon", "Storm",
        "Viper", "Ghost", "Raven", "Wolf", "Hawk",
        "Nova", "Blaze", "Frost", "Apex", "Drift",
        "Surge", "Bolt", "Flare", "Ridge", "Pulse",
    ]

    static func generate() -> String {
        let adjective = adjectives.randomElement() ?? "Echo"
        let number = Int.random(in: 1...99)
        return "\(adjective)-\(number)"
    }
}
