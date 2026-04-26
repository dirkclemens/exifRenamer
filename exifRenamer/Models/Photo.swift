import Foundation

enum PhotoStatus {
    case pending, renamed, skipped, conflict, failed(String)
}

@Observable
class Photo: Identifiable {
    let id = UUID()
    let url: URL
    var bookmarkData: Data?          // security-scoped bookmark for sandbox access
    var exifData: EXIFData?
    var proposedName: String = ""
    var status: PhotoStatus = .pending

    var dirBookmarkData: Data?   // security-scoped bookmark for parent directory

    init(url: URL) {
        self.url = url
        self.bookmarkData = Self.makeBookmark(for: url)
        self.dirBookmarkData = Self.makeBookmark(for: url.deletingLastPathComponent())
        DebugLog.info("Photo init: \(url.path), fileBookmark=\(self.bookmarkData != nil), dirBookmark=\(self.dirBookmarkData != nil)")
    }

    var originalName: String { url.lastPathComponent }

    func withScopedAccess<T>(_ work: (URL) throws -> T) throws -> T {
        let (resolved, isScoped) = resolvedURL()
        DebugLog.info("withScopedAccess: original=\(url.path), resolved=\(resolved.path), isScoped=\(isScoped)")

        // Also resolve the parent directory bookmark — moveItem needs write access to the folder
        var dirStale = false
        let dirResolved: URL?
        if let data = dirBookmarkData {
            dirResolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &dirStale)
        } else {
            dirResolved = nil
        }

        let startedDir  = dirResolved.map  { $0.startAccessingSecurityScopedResource() } ?? false
        let startedFile = isScoped ? resolved.startAccessingSecurityScopedResource() : false
        DebugLog.info("startAccessing: file=\(resolved.lastPathComponent), fileStarted=\(startedFile), dirStarted=\(startedDir)")

        defer {
            if startedFile { resolved.stopAccessingSecurityScopedResource() }
            if startedDir  { dirResolved?.stopAccessingSecurityScopedResource() }
            DebugLog.info("stopAccessing: \(resolved.lastPathComponent)")
        }

        if isScoped && !startedFile {
            let msg = "Security-scoped access could not be started for \(resolved.lastPathComponent)."
            DebugLog.error(msg)
            throw NSError(domain: "ExifRenamer", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return try work(resolved)
    }

    /// Resolves a fresh security-scoped URL from the stored bookmark (or falls back to url).
    func resolvedURL() -> (URL, Bool) {
        guard let data = bookmarkData else {
            DebugLog.error("resolvedURL: no bookmarkData for \(url.path)")
            return (url, false)
        }

        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            DebugLog.error("resolvedURL: failed to resolve bookmark for \(url.path)")
            return (url, false)
        }

        // Refresh stale bookmark so next operations keep working.
        if stale {
            DebugLog.info("resolvedURL: stale bookmark for \(resolved.path), refreshing")
            bookmarkData = Self.makeBookmark(for: resolved) ?? data
        }

        DebugLog.info("resolvedURL: success path=\(resolved.path), stale=\(stale)")
        return (resolved, true)
    }

    private static func makeBookmark(for url: URL) -> Data? {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data
        } catch {
            DebugLog.error("makeBookmark failed for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
}
