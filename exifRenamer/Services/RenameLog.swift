import AppKit
import Foundation

/// Optional tab-separated log of every rename batch (and undo) in
/// `~/Library/Application Support/exifRenamer/Logs` (inside the app container when sandboxed).
enum RenameLog {
    static let enabledKey = "writeRenameLog"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exifRenamer/Logs", isDirectory: true)
    }

    /// Writes one log file per batch. Returns the file URL, or nil if disabled / nothing to log.
    @discardableResult
    static func write(_ operations: [FileOperation], action: String) -> URL? {
        guard isEnabled, !operations.isEmpty else { return nil }
        let now = Date()
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let file = directory.appendingPathComponent("\(stamp)-\(action).tsv")
        var text = "# exifRenamer \(action) \(now.formatted(.iso8601))\nkind\tsource\tdestination\n"
        for op in operations {
            text += "\(op.kind.rawValue)\t\(op.source?.path ?? "")\t\(op.destination.path)\n"
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            DebugLog.info("RenameLog: wrote \(file.path)")
            return file
        } catch {
            DebugLog.error("RenameLog: writing failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func revealInFinder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }
}
