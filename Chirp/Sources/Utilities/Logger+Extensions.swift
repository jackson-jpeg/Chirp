import OSLog

extension Logger {
    private static let subsystem = Constants.subsystem

    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ptt = Logger(subsystem: subsystem, category: "ptt")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let wifiAware = Logger(subsystem: subsystem, category: "wifiAware")
    static let textMessage = Logger(subsystem: subsystem, category: "TextMessage")
    static let bleScanner = Logger(subsystem: subsystem, category: "BLEScanner")
    static let meshCloud = Logger(subsystem: subsystem, category: "MeshCloud")
}
