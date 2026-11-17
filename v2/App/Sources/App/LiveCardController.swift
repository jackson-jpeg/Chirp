import ActivityKit
import ChirpCore
import Foundation

/// Starts, updates and ends the Lock Screen and Dynamic Island card.
///
/// - Started only while the app is in use: from the Mesh heartbeat, which
///   runs only in the foreground with the radio on (the first tap that needs
///   other phones), never at launch.
/// - Updated from Dispatch events through ChirpCore's `LiveCard` (who talked
///   last, their words) and spaced by `LiveCardPacer`; a refused push is
///   retried once the interval has passed, with whatever is newest then.
/// - Goes stale after `staleAfter` without news, so an old card greys out
///   instead of claiming someone is talking.
@MainActor
final class LiveCardController {
    static let staleAfter: TimeInterval = 15 * 60

    private var activity: Activity<ChirpActivity>?
    private var card: LiveCard?
    private var pacer = LiveCardPacer()
    private var retry: Task<Void, Never>?

    var isRunning: Bool { activity != nil }

    /// Idempotent: a second call while a card is up only refreshes the count.
    func start(flock: String, onLine: Int) {
        if activity != nil { setOnLine(onLine); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let first = LiveCard(flock: flock, onLine: onLine)
        do {
            activity = try Activity.request(attributes: ChirpActivity(flockID: flock),
                                            content: content(first), pushType: nil)
            card = first
            _ = pacer.shouldPush(first, now: .now)
        } catch {
            activity = nil   // turned off in Settings, or too many running: no card, nothing else changes
        }
    }

    func setOnLine(_ n: Int) {
        guard var c = card, c.onLine != n else { return }
        c.onLine = n
        card = c
        push()
    }

    func apply(_ event: Dispatch.Event, person: (PeerID) -> (name: String, palette: UInt8)?) {
        guard let c = card, let next = c.applying(event, person: person) else { return }
        card = next
        push()
    }

    func end() {
        retry?.cancel()
        retry = nil
        guard let a = activity else { return }
        activity = nil
        card = nil
        let h = Handle(activity: a)
        Task.detached { await h.activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func content(_ c: LiveCard) -> ActivityContent<LiveCard> {
        ActivityContent(state: c, staleDate: Date().addingTimeInterval(Self.staleAfter))
    }

    private func push() {
        guard let a = activity, let c = card else { return }
        if pacer.shouldPush(c, now: .now) {
            let next = content(c)
            let h = Handle(activity: a)
            Task.detached { await h.activity.update(next) }
        } else if retry == nil {
            retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(LiveCardPacer.interval))
                guard !Task.isCancelled else { return }
                self?.retry = nil
                self?.push()
            }
        }
    }
}

/// ActivityKit's `Activity` is not marked Sendable in the iOS 26 SDK, while
/// its `update` and `end` are nonisolated async; it is documented as safe to
/// use from any thread, so it crosses to a detached task in this box.
private struct Handle: @unchecked Sendable {
    let activity: Activity<ChirpActivity>
}
