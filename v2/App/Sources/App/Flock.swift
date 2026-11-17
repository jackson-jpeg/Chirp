import SwiftUI
import ChirpCore

/// A person on the line, as the screens show them.
struct Person: Identifiable, Hashable {
    let id: String
    var name: String
    var palette: BirdPalette
    /// Their start-talking chirp: 0 Finch, 1 Robin, 2 Wren (ChirpCore `Bird.chirp`).
    var chirp: Int = 0
    var isYou = false

    static func == (a: Person, b: Person) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// What the screens read. Until the transport and audio are wired in, the app
/// runs on Demo Mode content: the same flock the design files show (Maya, Jon,
/// Priya, Sam on "Ski trip"), entering through this one model. Screen-specific
/// demo content lives next to each screen (`Flock+<Screen>.swift`).
@Observable
final class Flock {
    var flockName: String
    var you: Person
    var others: [Person]
    /// Who has the line right now (nil when it is quiet).
    var talkerID: String?

    init(flockName: String, you: Person, others: [Person], talkerID: String?) {
        self.flockName = flockName
        self.you = you
        let blocked = Flock.loadBlocked()
        self.others = others.filter { !blocked.contains($0.id) }
        self.talkerID = talkerID.flatMap { blocked.contains($0) ? nil : $0 }
    }

    /// People you blocked (App Review 5.1.2(i)). Kept across launches. A
    /// blocked person leaves Nearby, the wire and Chat, and in the transport
    /// ChirpCore's `BlockList` drops their packets both ways.
    private(set) var blockedIDs: Set<String> = Flock.loadBlocked()

    func block(_ id: String) {
        blockedIDs.insert(id)
        others.removeAll { $0.id == id }
        if talkerID == id { talkerID = nil }
        UserDefaults.standard.set(Array(blockedIDs), forKey: "blockedIDs")
    }

    func isBlocked(_ id: String) -> Bool { blockedIDs.contains(id) }

    private static func loadBlocked() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "blockedIDs") ?? [])
    }

    var everyone: [Person] { [you] + others }
    func person(_ id: String) -> Person? { everyone.first { $0.id == id } }
    var talker: Person? { talkerID.flatMap(person) }

    static let maya = Person(id: "maya", name: "Maya", palette: .yellow)
    static let jon = Person(id: "jon", name: "Jon", palette: .green)
    static let priya = Person(id: "priya", name: "Priya", palette: .lilac)
    static let sam = Person(id: "sam", name: "Sam", palette: .coral)

    static var demo: Flock {
        Flock(flockName: "Ski trip",
              you: Person(id: "you", name: "Jackson", palette: .blue, isYou: true),
              others: [maya, jon, priya],
              talkerID: "maya")
    }
}
