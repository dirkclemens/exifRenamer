import AppKit
import Foundation

/// Manages directory-level security-scoped access granted via NSOpenPanel.
/// Drag & drop only grants file-level access; write access to a folder requires NSOpenPanel.
class FolderAccessManager {
    static let shared = FolderAccessManager()

    // directory path → security-scoped bookmark data obtained via NSOpenPanel
    private var bookmarks: [String: Data] = [:]

    /// Ensures the app has write access to `directory`.
    /// If not yet granted, shows NSOpenPanel pre-navigated to that directory.
    /// Returns `true` if access was granted.
    @discardableResult
    func requestAccess(to directory: URL) -> Bool {
        let key = directory.standardized.path

        // Already have a valid bookmark?
        if let data = bookmarks[key] {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                if !stale {
                    DebugLog.info("FolderAccess: already granted for \(key)")
                    return true
                }
                // Stale — fall through to re-request
                DebugLog.info("FolderAccess: stale bookmark for \(key), re-requesting")
            }
        }

        DebugLog.info("FolderAccess: requesting access for \(key)")

        let panel = NSOpenPanel()
        panel.message = "Bitte gewähre Zugriff auf den Ordner \"\(directory.lastPathComponent)\", um Dateien darin umbenennen zu können."
        panel.prompt = "Zugriff gewähren"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory

        guard panel.runModal() == .OK, let chosen = panel.url else {
            DebugLog.error("FolderAccess: user denied access for \(key)")
            return false
        }

        guard chosen.standardized.path == key else {
            DebugLog.error("FolderAccess: user chose wrong folder: \(chosen.path) vs \(key)")
            return false
        }

        if let data = try? chosen.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[key] = data
            DebugLog.info("FolderAccess: bookmark stored for \(key)")
            return true
        }

        DebugLog.error("FolderAccess: could not create bookmark for \(chosen.path)")
        return false
    }

    /// Start accessing a previously granted directory. Returns the scoped URL and whether it was started.
    func startAccessing(directory: URL) -> (URL?, Bool) {
        let key = directory.standardized.path
        guard let data = bookmarks[key] else { return (nil, false) }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return (nil, false) }
        let started = resolved.startAccessingSecurityScopedResource()
        DebugLog.info("FolderAccess startAccessing: \(key), started=\(started)")
        return (resolved, started)
    }

    func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
        DebugLog.info("FolderAccess stopAccessing: \(url.path)")
    }
}
