import Foundation

enum RenameResult {
    case success(URL)
    case skipped
    case failed(Error)
}
