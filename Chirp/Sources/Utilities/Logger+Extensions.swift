import OSLog

extension Logger {
    private static let subsystem = Constants.subsystem

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ptt = Logger(subsystem: subsystem, category: "ptt")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let textMessage = Logger(subsystem: subsystem, category: "TextMessage")
    static let transport = Logger(subsystem: subsystem, category: "Transport")
    static let database = Logger(subsystem: subsystem, category: "Database")
}
