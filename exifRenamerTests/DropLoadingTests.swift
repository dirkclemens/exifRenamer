import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import exifRenamer

@MainActor
struct DropLoadingTests {
    /// Item provider callbacks arrive on background queues — must not trip Swift 6 isolation checks.
    @Test func loadsFileURLsFromItemProviders() async {
        let dir = TempDir()
        let files = [dir.file("a.jpg"), dir.file("b.jpg"), dir.file("c.jpg")]
        let providers = files.map { NSItemProvider(contentsOf: $0)! }
        let urls: [URL] = await withCheckedContinuation { cont in
            DropZoneView.loadFileURLs(from: providers) { cont.resume(returning: $0) }
        }
        #expect(Set(urls.map(\.lastPathComponent)) == ["a.jpg", "b.jpg", "c.jpg"])
    }
}
