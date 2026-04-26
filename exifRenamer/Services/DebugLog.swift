import Foundation
import OSLog

enum DebugLog {
    private static let logger = Logger(subsystem: "exifRenamer", category: "debug")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
