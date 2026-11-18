import SwiftUI

/// How one person is reached, as Nearby shows them.
struct NearbyEntry: Identifiable {
    enum Route: Equatable {
        case direct(strength: String)
        case through(Person)
    }

    var person: Person
    var route: Route
    var distance: String?
    var direction: String?
    /// The arrow's rotation in the file (`rotate(45deg)` and so on; 0 points up).
    var arrowDegrees: Double = 0
    /// Where the scene draws them (the `<g>` translate) and their name label's baseline.
    var sceneCenter: CGPoint?
    var labelBaseline: CGFloat = 132
    /// They are sharing where they are (a check-in to your flock).
    var checkedIn = false

    var id: String { person.id }

    var isDirect: Bool {
        if case .direct = route { return true }
        return false
    }

    var statusText: String {
        let how: String = switch route {
        case .direct(let strength): "Direct · \(strength)"
        case .through(let p): "Through \(p.name)'s phone"
        }
        return checkedIn ? how + " · sharing where they are" : how
    }

    /// A distance as the rows show it: "40 m", "1.2 km".
    static func metres(_ m: Double) -> String {
        m < 1000 ? "\(Int((m / 10).rounded() * 10)) m" : String(format: "%.1f km", m / 1000)
    }

    var accessibilitySummary: String {
        var parts = [person.name, statusText]
        if let distance { parts.append(distance.replacingOccurrences(of: " m", with: " meters")) }
        if let direction { parts.append(direction) }
        return parts.joined(separator: ", ")
    }
}

extension NearbyEntry {
    /// The rows of `Nearby.dc.html`, keyed by person.
    static func demo(for person: Person) -> NearbyEntry {
        switch person.id {
        case Flock.maya.id:
            NearbyEntry(person: person, route: .direct(strength: "strong"), distance: "140 m", direction: "Uphill",
                        arrowDegrees: 45, sceneCenter: CGPoint(x: 124, y: 84), labelBaseline: 136)
        case Flock.jon.id:
            NearbyEntry(person: person, route: .direct(strength: "strong"), distance: "60 m", direction: "Behind you",
                        arrowDegrees: 190, sceneCenter: CGPoint(x: 200, y: 77), labelBaseline: 134)
        case Flock.priya.id:
            NearbyEntry(person: person, route: .through(Flock.jon), distance: "640 m", direction: "Downhill",
                        arrowDegrees: 260, sceneCenter: CGPoint(x: 318, y: 75), labelBaseline: 128)
        default:
            NearbyEntry(person: person, route: .direct(strength: "good"))
        }
    }
}

