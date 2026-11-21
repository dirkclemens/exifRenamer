import Foundation

enum PhotoStatus {
    case pending, renamed, skipped, failed(String)
}

@Observable
class Photo: Identifiable {
    let id = UUID()
    let url: URL
    var bookmarkData: Data?          // security-scoped bookmark for sandbox access
    var exifData: EXIFData?
    var proposedName: String = ""
    var status: PhotoStatus = .pending

    /// - Parameter bookmarkData: pass a bookmark created off the main thread; nil creates one here.
    init(url: URL, bookmarkData: Data? = nil) {
        self.url = url
        self.bookmarkData = bookmarkData ?? Self.makeBookmark(for: url)
        DebugLog.info("Photo init: \(url.path), fileBookmark=\(self.bookmarkData != nil)")
    }

    var originalName: String { url.lastPathComponent }

    /// Runs `work` with security-scoped access to the (bookmark-resolved, i.e. current) file URL.
    /// Folder-level access is handled separately by `FolderAccessManager`.
    func withScopedAccess<T>(_ work: (URL) async throws -> T) async throws -> T {
        let (resolved, isScoped) = resolvedURL()
        let startedFile = isScoped ? resolved.startAccessingSecurityScopedResource() : false
        DebugLog.info("withScopedAccess: original=\(url.path), resolved=\(resolved.path), isScoped=\(isScoped), started=\(startedFile)")
        defer { if startedFile { resolved.stopAccessingSecurityScopedResource() } }

        if isScoped && !startedFile {
            let msg = String(localized: "Security-scoped access could not be started for \(resolved.lastPathComponent).")
            DebugLog.error(msg)
            throw NSError(domain: "ExifRenamer", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return try await work(resolved)
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

    nonisolated static func makeBookmark(for url: URL) -> Data? {
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
