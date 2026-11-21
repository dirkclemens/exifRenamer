import Foundation

enum ExifRenamerError: LocalizedError {
    case noProposedName, fileExists, writeFailed(String), noFolderAccess(String)
    var errorDescription: String? {
        switch self {
        case .noProposedName:        return String(localized: "No proposed name generated.")
        case .fileExists:            return String(localized: "File already exists.")
        case .writeFailed(let m):    return String(localized: "Write failed: \(m)")
        case .noFolderAccess(let f): return String(localized: "No access to folder \"\(f)\".")
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
        includeSidecars: Bool = true,
        access: FolderAccessing? = nil,
        progress: (Int) -> Void = { _ in }
    ) async -> RenameBatch {
        let access = access ?? FolderAccessManager.shared
        var batch = RenameBatch()
        let fm = FileManager.default
        let renameInPlace: Bool = { if case .sameFolder = outputMode { return true } else { return false } }()
        let moveFiles = renameInPlace && !createFolders

        // Current location of every source file in this batch (bookmarks follow earlier renames).
        let sourceURLs = photos.map { $0.resolvedURL().0 }

        // Ask for folder access once per source folder, before touching any file —
        // instead of one dialog per photo (and again after every "Cancel").
        var deniedDirs = Set<String>()
        if renameInPlace {
            let dirs = Set(sourceURLs.map { $0.deletingLastPathComponent().standardizedFileURL })
            for dir in dirs.sorted(by: { $0.path < $1.path }) where !access.requestAccess(to: dir) {
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
                batch.results.append(.failed(ExifRenamerError.noProposedName))
                continue
            }

            DebugLog.info("Rename start: original=\(photo.originalName), proposed=\(name)")

            var ops: [FileOperation] = []
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
                        let (dir, started) = access.startAccessing(directory: sourceDir)
                        if started { scopedDir = dir }
                    }
                    defer { if let d = scopedDir { access.stopAccessing(url: d) } }

                    let destDir: URL
                    if createFolders {
                        let (url, created) = try FolderOrganizer.resolvedFolder(for: photo, style: style, baseDestination: baseDir)
                        destDir = url
                        ops += created.map { FileOperation(kind: .createFolder, source: nil, destination: $0) }
                    } else {
                        destDir = baseDir
                    }
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
                    } else if fm.fileExists(atPath: destURL.path) {
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
                            ops.append(try replaceExisting(destURL, fm: fm))
                        case .autoNumber:
                            destURL = autoNumbered(destURL, fm: fm)
                            DebugLog.info("Conflict autonumber: new dest=\(destURL.path)")
                        }
                    }

                    let src = sourceURL, dst = destURL
                    try await transfer(src, to: dst, move: moveFiles)
                    ops.append(FileOperation(kind: moveFiles ? .move : .copy, source: src, destination: dst))
                    writtenDests.insert(key(dst))
                    DebugLog.info("\(moveFiles ? "Move" : "Copy") success: \(src.lastPathComponent) -> \(dst.path)")

                    if includeSidecars {
                        ops += await processSidecars(of: src, mainDestination: dst, move: moveFiles,
                                                     fm: fm, writtenDests: &writtenDests)
                    }
                    return .success(dst)
                }
                batch.results.append(result)
            } catch {
                DebugLog.error("Rename failed for \(photo.originalName): \(error.localizedDescription)")
                batch.results.append(.failed(error))
            }
            // Folders created before a failure/skip are recorded too, so undo can clean them up.
            batch.operations += ops.map { var op = $0; op.photoID = photo.id; return op }
        }

        return batch
    }

    // MARK: - Undo

    struct UndoOutcome {
        var undone: [FileOperation] = []
        var failed = 0
        var notRestorable = 0   // overwritten files that stay in the Trash
    }

    /// Reverts the operations of a batch in reverse order: moves are moved back, copies and
    /// created (empty) folders are removed, overwritten files are put back from the Trash if possible.
    static func undo(_ operations: [FileOperation], access: FolderAccessing? = nil) async -> UndoOutcome {
        let access = access ?? FolderAccessManager.shared
        var outcome = UndoOutcome()
        let fm = FileManager.default

        // Hold folder access for every folder involved while undoing.
        let dirs = Set(operations.flatMap { op in
            [op.destination.deletingLastPathComponent(), op.source?.deletingLastPathComponent()].compactMap { $0 }
        })
        let scoped = dirs.compactMap { dir -> URL? in
            let (url, started) = access.startAccessing(directory: dir)
            return started ? url : nil
        }
        defer { scoped.forEach { access.stopAccessing(url: $0) } }

        for op in operations.reversed() {
            do {
                switch op.kind {
                case .move:
                    guard let src = op.source, fm.fileExists(atPath: op.destination.path),
                          !fm.fileExists(atPath: src.path) || isSameFile(src, op.destination)
                    else { outcome.failed += 1; continue }
                    let dst = op.destination
                    try await runIO { try FileManager.default.moveItem(at: dst, to: src) }
                case .copy:
                    guard fm.fileExists(atPath: op.destination.path) else { continue }
                    do { try fm.trashItem(at: op.destination, resultingItemURL: nil) }
                    catch { try fm.removeItem(at: op.destination) }
                case .trash:
                    guard let original = op.source, !fm.fileExists(atPath: original.path) else {
                        outcome.notRestorable += 1; continue
                    }
                    do { try fm.moveItem(at: op.destination, to: original) }
                    catch { outcome.notRestorable += 1; continue }
                case .delete:
                    outcome.notRestorable += 1
                    continue
                case .createFolder:
                    let contents = (try? fm.contentsOfDirectory(atPath: op.destination.path)) ?? []
                    guard contents.allSatisfy({ $0 == ".DS_Store" }) else { continue }
                    try fm.removeItem(at: op.destination)
                }
                outcome.undone.append(op)
            } catch {
                DebugLog.error("Undo failed for \(op.kind.rawValue) \(op.destination.path): \(error.localizedDescription)")
                outcome.failed += 1
            }
        }
        return outcome
    }

    // MARK: - Helpers

    /// "Overwrite": moves the existing file to the Trash (recoverable), or deletes it on volumes without Trash.
    private static func replaceExisting(_ url: URL, fm: FileManager) throws -> FileOperation {
        var trashed: NSURL?
        do {
            try fm.trashItem(at: url, resultingItemURL: &trashed)
            DebugLog.info("Conflict overwrite: trashed \(url.path)")
            return FileOperation(kind: .trash, source: url, destination: (trashed as URL?) ?? url)
        } catch {
            try fm.removeItem(at: url)
            DebugLog.info("Conflict overwrite: deleted \(url.path)")
            return FileOperation(kind: .delete, source: nil, destination: url)
        }
    }

    /// Renames/copies sidecars (`.xmp`, `.aae`) so they keep matching the main file.
    /// Never overwrites anything; a failing sidecar doesn't fail the photo.
    private static func processSidecars(of source: URL, mainDestination: URL, move: Bool,
                                        fm: FileManager, writtenDests: inout Set<String>) async -> [FileOperation] {
        var ops: [FileOperation] = []
        for sidecar in MediaScanner.sidecars(of: source) {
            let dest = mainDestination.deletingLastPathComponent()
                .appendingPathComponent(sidecar.name(forMainFileNamed: mainDestination.lastPathComponent))
            if isSameFile(sidecar.url, dest) {
                guard move, sidecar.url.lastPathComponent != dest.lastPathComponent else { continue }
            } else if fm.fileExists(atPath: dest.path) {
                DebugLog.info("Sidecar skipped, destination exists: \(dest.path)")
                continue
            }
            do {
                try await transfer(sidecar.url, to: dest, move: move)
                ops.append(FileOperation(kind: move ? .move : .copy, source: sidecar.url, destination: dest))
                writtenDests.insert(key(dest))
                DebugLog.info("Sidecar \(move ? "moved" : "copied"): \(sidecar.url.lastPathComponent) -> \(dest.lastPathComponent)")
            } catch {
                DebugLog.error("Sidecar failed: \(sidecar.url.path): \(error.localizedDescription)")
            }
        }
        return ops
    }

    private static func transfer(_ src: URL, to dst: URL, move: Bool) async throws {
        if move {
            try await runIO { try FileManager.default.moveItem(at: src, to: dst) }
        } else {
            try await runIO { try FileManager.default.copyItem(at: src, to: dst) }
        }
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
    static func isSameFile(_ a: URL, _ b: URL) -> Bool {
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
