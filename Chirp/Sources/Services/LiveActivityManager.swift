import ActivityKit
import Foundation
import OSLog

@MainActor
final class LiveActivityManager {

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.chirp.app", category: "LiveActivity")
    private var currentActivity: Activity<ChirpActivityAttributes>?

    // MARK: - Public API

    /// Start a Live Activity when joining a channel.
    func startActivity(channelName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities not enabled")
            return
        }

        let attributes = ChirpActivityAttributes(channelName: channelName)
        let initialState = ChirpActivityAttributes.ContentState(
            pttState: "idle",
            speakerName: nil,
            channelName: channelName,
            peerCount: 0,
            inputLevel: 0
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            logger.info("Started Live Activity: \(activity.id)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    /// Update the Live Activity with current PTT state.
    func updateActivity(
        state: PTTState,
        channelName: String,
        peerCount: Int,
        inputLevel: Double
    ) {
        guard let activity = currentActivity else { return }

        let pttStateString: String
        var speakerName: String?

        switch state {
        case .idle:
            pttStateString = "idle"
        case .transmitting:
            pttStateString = "transmitting"
        case .receiving(let name, _):
            pttStateString = "receiving"
            speakerName = name
        case .denied:
            pttStateString = "denied"
        }

        let updatedState = ChirpActivityAttributes.ContentState(
            pttState: pttStateString,
            speakerName: speakerName,
            channelName: channelName,
            peerCount: peerCount,
            inputLevel: inputLevel
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
        }
    }

    /// End the Live Activity when leaving a channel.
    func endActivity() {
        guard let activity = currentActivity else { return }

        let finalState = ChirpActivityAttributes.ContentState(
            pttState: "idle",
            speakerName: nil,
            channelName: "",
            peerCount: 0,
            inputLevel: 0
        )

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        currentActivity = nil
        logger.info("Ended Live Activity")
    }
}
