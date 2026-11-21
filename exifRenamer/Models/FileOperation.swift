import Foundation

/// One file system change made by a rename batch — used for undo and the rename log.
nonisolated struct FileOperation: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case move          // source renamed/moved to destination
        case copy          // destination created as a copy of source
        case trash         // existing file at `source` replaced ("Overwrite"); now at `destination` in the Trash
        case delete        // existing file at `destination` deleted (volume without Trash) — not undoable
        case createFolder  // folder created at `destination`
    }

    let kind: Kind
    let source: URL?
    let destination: URL
    var photoID: UUID?
}

/// Result of `RenameService.process`: one result per photo plus every file operation performed.
struct RenameBatch {
    var results: [RenameResult] = []
    var operations: [FileOperation] = []
}
