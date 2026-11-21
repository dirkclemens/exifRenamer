import Foundation

enum ExifRenamerError: LocalizedError {
    case noProposedName, fileExists, writeFailed(String), noFolderAccess(String)
    var errorDescription: String? {
        switch self {
        case .noProposedName:       return "No proposed name generated."
        case .fileExists:           return "File already exists."
        case .writeFailed(let m):   return "Write failed: \(m)"
        case .noFolderAccess(let f): return "No access to folder \"\(f)\"."
        }
    }
}

struct RenameService {
    static func process(
        photos: [Photo],
        style: NamingStyle,
        outputMode: OutputMode,
        conflictStrategy: ConflictStrategy,
        createFolders: Bool,
        progress: (Int) -> Void = { _ in }
    ) async -> [RenameResult] {
        var results: [RenameResult] = []
        let fm = FileManager.default
        let fam = FolderAccessManager.shared
        let renameInPlace: Bool = { if case .sameFolder = outputMode { return true } else { return false } }()
        let moveFiles = renameInPlace && !createFolders

        // Current location of every source file in this batch (bookmarks follow earlier renames).
        let sourceURLs = photos.map { $0.resolvedURL().0 }

        // Ask for folder access once per source folder, before touching any file —
        // instead of one dialog per photo (and again after every "Cancel").
        var deniedDirs = Set<String>()
        if renameInPlace {
            let dirs = Set(sourceURLs.map { $0.deletingLastPathComponent().standardizedFileURL })
            for dir in dirs.sorted(by: { $0.path < $1.path }) where !fam.requestAccess(to: dir) {
                deniedDirs.insert(key(dir))
            }
        }

        // Files that must never be overwritten in this batch: sources not yet processed
        // (e.g. A→"x.jpg" while "x.jpg" is B, still waiting) and files already written.
        var pendingSources = Set(sourceURLs.map(key))
        var writtenDests = Set<String>()

        for (index, photo) in photos.enumerated() {
            defer {
                pendingSources.remove(key(sourceURLs[index]))
                progress(index + 1)
            }

            let name = photo.proposedName
            guard !name.isEmpty else {
                DebugLog.error("Rename skipped: no proposed name for \(photo.originalName)")
                results.append(.failed(ExifRenamerError.noProposedName))
                continue
            }

            DebugLog.info("Rename start: original=\(photo.originalName), proposed=\(name)")

            do {
                let result: RenameResult = try await photo.withScopedAccess { sourceURL in
                    let sourceDir = sourceURL.deletingLastPathComponent()

                    let baseDir: URL
                    switch outputMode {
                    case .sameFolder:          baseDir = sourceDir
                    case .customFolder(let u): baseDir = u
                    }

                    // Folder write access must be active *before* creating subfolders or moving.
                    var scopedDir: URL?
                    if renameInPlace {
                        guard !deniedDirs.contains(key(sourceDir)) else {
                            throw ExifRenamerError.noFolderAccess(sourceDir.lastPathComponent)
                        }
                        let (dir, started) = fam.startAccessing(directory: sourceDir)
                        if started { scopedDir = dir }
                    }
                    defer { if let d = scopedDir { fam.stopAccessing(url: d) } }

                    let destDir = createFolders
                        ? try FolderOrganizer.resolvedFolder(for: photo, style: style, baseDestination: baseDir)
                        : baseDir
                    var destURL = destDir.appendingPathComponent(name)
                    DebugLog.info("Rename paths: source=\(sourceURL.path), dest=\(destURL.path)")

                    // Destination is the source file itself (already named like this, or a
                    // case-only change on a case-insensitive volume). Must be checked BEFORE
                    // conflict handling — otherwise "Overwrite" would delete the source.
                    if isSameFile(sourceURL, destURL) {
                        if sourceURL.lastPathComponent == destURL.lastPathComponent || !moveFiles {
                            DebugLog.info("Rename skipped: source already has the target name")
                            return .skipped
                        }
                        let src = sourceURL, dst = destURL
                        try await runIO { try FileManager.default.moveItem(at: src, to: dst) }
                        writtenDests.insert(key(destURL))
                        return .success(destURL)
                    }

                    if fm.fileExists(atPath: destURL.path) {
                        var strategy = conflictStrategy
                        let protected = pendingSources.contains(key(destURL)) || writtenDests.contains(key(destURL))
                        if strategy == .overwrite && protected {
                            DebugLog.info("Conflict with a file of this batch — auto-numbering instead of overwriting")
                            strategy = .autoNumber
                        }
                        DebugLog.info("Conflict at \(destURL.path), strategy=\(strategy.rawValue)")
                        switch strategy {
                        case .skip:
                            return .skipped
                        case .overwrite:
                            // Move the replaced file to the Trash so it can be recovered.
                            do { try fm.trashItem(at: destURL, resultingItemURL: nil) }
                            catch { try fm.removeItem(at: destURL) }
                            DebugLog.info("Conflict overwrite: removed \(destURL.path)")
                        case .autoNumber:
                            destURL = autoNumbered(destURL, fm: fm)
                            DebugLog.info("Conflict autonumber: new dest=\(destURL.path)")
                        }
                    }

                    let src = sourceURL, dst = destURL
                    if moveFiles {
                        try await runIO { try FileManager.default.moveItem(at: src, to: dst) }
                        DebugLog.info("Move success: \(src.lastPathComponent) -> \(dst.lastPathComponent)")
                    } else {
                        try await runIO { try FileManager.default.copyItem(at: src, to: dst) }
                        DebugLog.info("Copy success: \(src.lastPathComponent) -> \(dst.path)")
                    }
                    writtenDests.insert(key(destURL))
                    return .success(destURL)
                }
                results.append(result)
            } catch {
                DebugLog.error("Rename failed for \(photo.originalName): \(error.localizedDescription)")
                results.append(.failed(error))
            }
        }

        return results
    }

    /// Runs blocking file I/O (large RAW copies) off the main actor so the UI stays responsive.
    private static func runIO(_ body: @escaping @Sendable () throws -> Void) async throws {
        try await Task.detached(priority: .userInitiated, operation: body).value
    }

    /// Normalized path key (case-insensitive, like the default APFS volume format).
    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }

    /// True if both URLs refer to the same file system object.
    private static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        guard let idA = (try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier,
              let idB = (try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
        else { return false }
        return idA.isEqual(idB)
    }

    private static func autoNumbered(_ url: URL, fm: FileManager) -> URL {
        let dir  = url.deletingLastPathComponent()
        let ext  = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        var candidate = url
        while fm.fileExists(atPath: candidate.path) {
            let numbered = base + FormatEngine.counterSuffix(i)
            candidate = dir.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
            i += 1
        }
        return candidate
    }
}
