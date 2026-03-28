enum PTTState: Equatable, Sendable {
    case idle
    case transmitting
    case receiving(speakerName: String, speakerID: String)
    case denied
}
