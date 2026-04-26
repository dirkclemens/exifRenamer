import Foundation

enum ExifRenamerError: LocalizedError {
    case noProposedName, fileExists, writeFailed(String)
    var errorDescription: String? {
        switch self {
        case .noProposedName:      return "No proposed name generated."
        case .fileExists:          return "File already exists."
        case .writeFailed(let m):  return "Write failed: \(m)"
        }
    }
}

struct RenameService {
    static func process(
        photos: [Photo],
        style: NamingStyle,
        outputMode: OutputMode,
        conflictStrategy: ConflictStrategy,
        createFolders: Bool
    ) async -> [RenameResult] {
        var results: [RenameResult] = []
        let fm = FileManager.default

        for photo in photos {
            let name = photo.proposedName
            guard !name.isEmpty else {
                DebugLog.error("Rename skipped: no proposed name for \(photo.originalName)")
                results.append(.failed(ExifRenamerError.noProposedName))
                continue
            }

            DebugLog.info("Rename start: original=\(photo.originalName), proposed=\(name)")

            do {
                let result: RenameResult = try photo.withScopedAccess { sourceURL in
                    let sourceDir = sourceURL.deletingLastPathComponent()

                    let baseDir: URL
                    switch outputMode {
                    case .sameFolder:          baseDir = sourceDir
                    case .customFolder(let u): baseDir = u
                    }

                    let destDir: URL
                    if createFolders {
                        destDir = try FolderOrganizer.resolvedFolder(for: photo, style: style, baseDestination: baseDir)
                    } else {
                        destDir = baseDir
                    }

                    var destURL = destDir.appendingPathComponent(name)
                    DebugLog.info("Rename paths: source=\(sourceURL.path), dest=\(destURL.path)")

                    // Request directory-level write access (drag & drop only gives file-level access)
                    let fam = FolderAccessManager.shared
                    guard fam.requestAccess(to: sourceDir) else {
                        throw NSError(domain: "ExifRenamer", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "Kein Zugriff auf Ordner \"\(sourceDir.lastPathComponent)\"."
                        ])
                    }
                    let (scopedDir, dirStarted) = fam.startAccessing(directory: sourceDir)
                    defer { if dirStarted, let sd = scopedDir { fam.stopAccessing(url: sd) } }

                    if fm.fileExists(atPath: destURL.path) {
                        DebugLog.info("Conflict at \(destURL.path), strategy=\(conflictStrategy.rawValue)")
                        switch conflictStrategy {
                        case .skip:
                            return .skipped
                        case .overwrite:
                            try fm.removeItem(at: destURL)
                            DebugLog.info("Conflict overwrite: removed \(destURL.path)")
                        case .autoNumber:
                            destURL = autoNumbered(destURL, fm: fm)
                            DebugLog.info("Conflict autonumber: new dest=\(destURL.path)")
                        }
                    }

                    let isSameFolder = sourceDir.standardized == destDir.standardized
                    if isSameFolder && destURL.lastPathComponent == sourceURL.lastPathComponent {
                        DebugLog.info("Rename skipped: identical source and dest filename")
                        return .skipped
                    }

                    if case .sameFolder = outputMode, !createFolders {
                        try fm.moveItem(at: sourceURL, to: destURL)
                        DebugLog.info("Move success: \(sourceURL.lastPathComponent) -> \(destURL.lastPathComponent)")
                    } else {
                        try fm.copyItem(at: sourceURL, to: destURL)
                        DebugLog.info("Copy success: \(sourceURL.lastPathComponent) -> \(destURL.lastPathComponent)")
                    }

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

    private static func autoNumbered(_ url: URL, fm: FileManager) -> URL {
        let dir  = url.deletingLastPathComponent()
        let ext  = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var i = 1
        var candidate = url
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)_\(i)" : "\(base)_\(i).\(ext)"
            candidate = dir.appendingPathComponent(name)
            i += 1
        }
        return candidate
    }
}
