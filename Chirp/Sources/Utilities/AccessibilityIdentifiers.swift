import Foundation

/// String constants for accessibility identifiers, used in UI test automation.
enum AccessibilityID {
    // MARK: - Home
    static let homeView = "homeView"
    static let channelCard = "channelCard"
    static let meshMapButton = "meshMapButton"
    static let settingsButton = "settingsButton"
    static let newChannelButton = "newChannelButton"
    static let sosButton = "sosButton"
    static let gatewayButton = "gatewayButton"
    static let friendsRow = "friendsRow"
    static let createFirstChannel = "createFirstChannel"

    // MARK: - Channel
    static let channelView = "channelView"
    static let pttButton = "pttButton"
    static let modePicker = "modePicker"
    static let quickActionCamera = "quickActionCamera"
    static let quickActionChat = "quickActionChat"
    static let quickActionLocation = "quickActionLocation"
    static let quickActionSOS = "quickActionSOS"
    static let statusPill = "statusPill"
    static let peerCountPill = "peerCountPill"
    static let waveform = "waveform"

    // MARK: - Mesh Map
    static let meshMap = "meshMap"
    static let meshMapCanvas = "meshMapCanvas"
    static let meshHealthScore = "meshHealthScore"
    static let meshStatsBar = "meshStatsBar"

    // MARK: - Settings
    static let settingsView = "settingsView"
    static let callsignField = "callsignField"
    static let speakerToggle = "speakerToggle"
    static let hapticToggle = "hapticToggle"
    static let chirpSoundsToggle = "chirpSoundsToggle"
    static let loopbackToggle = "loopbackToggle"
    static let emergencyModeToggle = "emergencyModeToggle"

    // MARK: - Chat
    static let chatView = "chatView"
    static let chatInputField = "chatInputField"
    static let chatSendButton = "chatSendButton"
    static let chatAttachmentMenu = "chatAttachmentMenu"

    // MARK: - Emergency
    static let emergencySOSView = "emergencySOSView"
    static let sosActivateButton = "sosActivateButton"
    static let sosCancelButton = "sosCancelButton"

    // MARK: - Onboarding
    static let onboardingView = "onboardingView"
    static let getStartedButton = "getStartedButton"

    // MARK: - Protect (V3)
    static let protectStatusBar = "protectStatusBar"
    static let protectTabPicker = "protectTabPicker"
    static let roomScannerView = "roomScannerView"
    static let scanButton = "scanButton"
    static let shareWithMeshButton = "shareWithMeshButton"
    static let privacyShieldView = "privacyShieldView"
    static let privacyScoreGauge = "privacyScoreGauge"
    static let soundAlertsView = "soundAlertsView"
    static let meshCloudView = "meshCloudView"
    static let storageDonationToggle = "storageDonationToggle"

    // MARK: - File Transfer (V3)
    static let documentPickerButton = "documentPickerButton"
    static let fileTransferBubble = "fileTransferBubble"
}
