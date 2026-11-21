import AppKit
import Foundation

/// Folder write access as needed by `RenameService` (abstracted so tests can grant access without dialogs).
protocol FolderAccessing: AnyObject {
    func requestAccess(to directory: URL) -> Bool
    func startAccessing(directory: URL) -> (URL?, Bool)
    func stopAccessing(url: URL)
}

/// Manages directory-level security-scoped access.
/// Dropping single files only grants file-level access; renaming/creating files in a
/// folder requires folder access, granted via NSOpenPanel or by dropping the folder itself.
/// Access to a folder covers all of its subfolders.
/// Granted folders are remembered across launches (app-scoped security bookmarks in UserDefaults).
class FolderAccessManager: FolderAccessing {
    static let shared = FolderAccessManager()
    private static let defaultsKey = "folderAccessBookmarks"

    // granted directory path → security-scoped bookmark data
    private var bookmarks: [String: Data] {
        didSet { UserDefaults.standard.set(bookmarks, forKey: Self.defaultsKey) }
    }

    init() {
        bookmarks = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]
    }

    /// Folders the app currently remembers access to.
    var grantedFolders: [String] { bookmarks.keys.sorted() }

    /// Forget all remembered folder permissions.
    func forgetAll() {
        bookmarks = [:]
        DebugLog.info("FolderAccess: all remembered folders forgotten")
    }

    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The granted directory key that covers `directory` (itself or an ancestor).
    private func grantedKey(covering directory: URL) -> String? {
        let path = Self.key(directory)
        return bookmarks.keys
            .filter { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .max { $0.count < $1.count }
    }

    /// Records a folder the app already has access to (e.g. a folder dropped onto the window).
    func registerGranted(directory: URL) {
        let k = Self.key(directory)
        guard bookmarks[k] == nil,
              let data = try? directory.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        bookmarks[k] = data
        DebugLog.info("FolderAccess: registered dropped folder \(k)")
    }

    /// Ensures the app has write access to `directory`.
    /// If not yet granted, shows NSOpenPanel pre-navigated to that directory.
    /// Choosing the folder itself or any parent folder is accepted.
    /// Returns `true` if access was granted.
    @discardableResult
    func requestAccess(to directory: URL) -> Bool {
        let key = Self.key(directory)

        // Already have a valid bookmark for it or a parent folder?
        if let granted = grantedKey(covering: directory), let data = bookmarks[granted] {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
               Self.key(resolved) == granted || !stale {
                DebugLog.info("FolderAccess: already granted for \(key) via \(granted)")
                return true
            }
            DebugLog.info("FolderAccess: stale bookmark for \(granted), re-requesting")
            bookmarks[granted] = nil
        }

        DebugLog.info("FolderAccess: requesting access for \(key)")

        let panel = NSOpenPanel()
        panel.message = "Please grant access to the folder \"\(directory.lastPathComponent)\" so files in it can be renamed."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory

        guard panel.runModal() == .OK, let chosen = panel.url else {
            DebugLog.error("FolderAccess: user denied access for \(key)")
            return false
        }

        let chosenKey = Self.key(chosen)
        guard key == chosenKey || key.hasPrefix(chosenKey.hasSuffix("/") ? chosenKey : chosenKey + "/") else {
            DebugLog.error("FolderAccess: user chose unrelated folder: \(chosenKey) vs \(key)")
            return false
        }

        if let data = try? chosen.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[chosenKey] = data
            DebugLog.info("FolderAccess: bookmark stored for \(chosenKey)")
            return true
        }

        DebugLog.error("FolderAccess: could not create bookmark for \(chosen.path)")
        return false
    }

    /// Start accessing a previously granted directory (or its granted parent).
    /// Returns the scoped URL and whether access was started.
    func startAccessing(directory: URL) -> (URL?, Bool) {
        guard let granted = grantedKey(covering: directory), let data = bookmarks[granted] else { return (nil, false) }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return (nil, false) }
        let started = resolved.startAccessingSecurityScopedResource()
        // Folder moved/renamed since the bookmark was made — refresh it while we have access.
        if stale, started,
           let fresh = try? resolved.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[granted] = nil
            bookmarks[Self.key(resolved)] = fresh
        }
        DebugLog.info("FolderAccess startAccessing: \(granted), started=\(started), stale=\(stale)")
        return (resolved, started)
    }

    func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
        DebugLog.info("FolderAccess stopAccessing: \(url.path)")
    }
}
