import Foundation

/// String constants for accessibility identifiers, used in UI test automation.
enum AccessibilityID {
    // MARK: - Home
    static let homeView = "homeView"
    static let channelCard = "channelCard"
    static let settingsButton = "settingsButton"
    static let newChannelButton = "newChannelButton"
    static let friendsRow = "friendsRow"
    static let createFirstChannel = "createFirstChannel"

    // MARK: - Channel
    static let channelView = "channelView"
    static let pttButton = "pttButton"
    static let modePicker = "modePicker"
    static let quickActionCamera = "quickActionCamera"
    static let quickActionChat = "quickActionChat"
    static let quickActionLocation = "quickActionLocation"
    static let statusPill = "statusPill"
    static let peerCountPill = "peerCountPill"
    static let waveform = "waveform"

    // MARK: - Settings
    static let settingsView = "settingsView"
    static let callsignField = "callsignField"
    static let speakerToggle = "speakerToggle"
    static let hapticToggle = "hapticToggle"
    static let chirpSoundsToggle = "chirpSoundsToggle"
    static let loopbackToggle = "loopbackToggle"

    // MARK: - Chat
    static let chatView = "chatView"
    static let chatInputField = "chatInputField"
    static let chatSendButton = "chatSendButton"
    static let chatAttachmentMenu = "chatAttachmentMenu"
    static let chatSearchField = "chatSearchField"
    static let chatVoiceNoteButton = "chatVoiceNoteButton"
    static let chatVoiceNoteBubble = "chatVoiceNoteBubble"
    static let chatTypingIndicator = "chatTypingIndicator"

    // MARK: - Onboarding
    static let onboardingView = "onboardingView"
    static let getStartedButton = "getStartedButton"

    // MARK: - Location check-in
    static let mapCheckInButton = "mapCheckInButton"
    static let mapStopSharingButton = "mapStopSharingButton"
    static let mapSharingIndicator = "mapSharingIndicator"
    static let locationContinue = "locationContinue"
    static let locationNotNow = "locationNotNow"
    static let locationCheckIn = "locationCheckIn"
    static let locationStopSharing = "locationStopSharing"

    // MARK: - File Transfer
    static let documentPickerButton = "documentPickerButton"
    static let fileTransferBubble = "fileTransferBubble"
}
