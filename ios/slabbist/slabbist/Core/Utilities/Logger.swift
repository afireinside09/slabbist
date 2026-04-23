import Foundation
import OSLog

enum AppLog {
    static let subsystem = "com.slabbist"

    static let app       = Logger(subsystem: subsystem, category: "app")
    static let auth      = Logger(subsystem: subsystem, category: "auth")
    static let sync      = Logger(subsystem: subsystem, category: "sync")
    static let outbox    = Logger(subsystem: subsystem, category: "outbox")
    static let camera    = Logger(subsystem: subsystem, category: "camera")
    static let ocr       = Logger(subsystem: subsystem, category: "ocr")
    static let lots      = Logger(subsystem: subsystem, category: "lots")
    static let scans     = Logger(subsystem: subsystem, category: "scans")
    static let network   = Logger(subsystem: subsystem, category: "network")
}
