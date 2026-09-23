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
    static let voiceNotePlayButton = "voiceNotePlayButton"
    static let chatTypingIndicator = "chatTypingIndicator"

    // MARK: - Onboarding
    static let onboardingView = "onboardingView"
    static let getStartedButton = "getStartedButton"

    // MARK: - Location check-in
    static let mapCheckInButton = "mapCheckInButton"
    static let mapStopSharingButton = "mapStopSharingButton"
    static let mapSharingIndicator = "mapSharingIndicator"
    // The app's own sharing consent, asked after iOS has granted permission
    // and asked again on every check-in. There is deliberately no identifier
    // for a screen before the system prompt, because there is no such screen:
    // Check In fires `requestWhenInUseAuthorization()` directly.
    static let locationConsentSheet = "locationConsentSheet"
    static let locationShareButton = "locationShareButton"
    static let locationDontShareButton = "locationDontShareButton"
    static let locationAboutLink = "locationAboutLink"
    static let locationAboutView = "locationAboutView"
    static let locationAboutSettingsRow = "locationAboutSettingsRow"

    // MARK: - Permissions
    static let onboardingMicPage = "onboardingMicPage"
    static let onboardingContinue = "onboardingContinue"
    static let micDeniedNotice = "micDeniedNotice"
    static let locationDeniedNotice = "locationDeniedNotice"
    static let openSettingsButton = "openSettingsButton"

    // MARK: - Demo Mode
    static let demoModeToggle = "demoModeToggle"
    static let tryDemoModeButton = "tryDemoModeButton"
    static let demoBadge = "demoBadge"
    static let demoExitButton = "demoExitButton"
    static let meshStatusLabel = "meshStatusLabel"
    /// The strip along the bottom of the home screen. A long press on it
    /// opens Diagnostics, which is the sixth place a peer can be blocked from.
    static let meshStatusStrip = "meshStatusStrip"
    static let peerCountBadge = "peerCountBadge"
    static let voiceMessagePlayButton = "voiceMessagePlayButton"
    static let mapPeerPin = "mapPeerPin"
    static let peerMap = "peerMap"

    // MARK: - Moderation
    // The one sheet every Block and Report goes through, from every surface a
    // peer appears on. See `PeerActionSheet`.
    static let peerActionSheet = "peerActionSheet"
    static let peerSheetBlockButton = "peerSheetBlockButton"
    static let peerSheetReportButton = "peerSheetReportButton"
    static let peerSheetBlockConfirm = "peerSheetBlockConfirm"
    static let reportReasonPicker = "reportReasonPicker"
    static let reportSendButton = "reportSendButton"
    static let blockedUsersRow = "blockedUsersRow"
    static let messageFilterToggle = "messageFilterToggle"
    static let hiddenMessageDisclosure = "hiddenMessageDisclosure"
    /// The one context-menu item that opens the peer sheet, carried by every
    /// surface a peer appears on: a message, a friend, a participant, a voice
    /// message and a Diagnostics node.
    static let blockOrReportMenuItem = "blockOrReportMenuItem"
    static let termsOfUseRow = "termsOfUseRow"

    // MARK: - File Transfer
    static let documentPickerButton = "documentPickerButton"
    static let fileTransferBubble = "fileTransferBubble"
}
