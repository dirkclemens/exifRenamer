import Foundation
import Testing
@testable import exifRenamer

@MainActor
struct MediaScannerTests {
    @Test func findsImagesRecursivelyAndSkipsOthers() {
        let dir = TempDir()
        dir.file("a.jpg"); dir.file("b.CR3"); dir.file("sub/c.heic"); dir.file("sub/d.ORF")
        dir.file("notes.txt"); dir.file("a.xmp"); dir.file(".hidden.jpg")
        let found = MediaScanner.imageFiles(in: [dir.url]).map(\.lastPathComponent)
        #expect(found == ["a.jpg", "b.CR3", "c.heic", "d.ORF"])
    }

    @Test func detectsBothSidecarStyles() {
        let dir = TempDir()
        let raw = dir.file("IMG_1.CR3")
        dir.file("IMG_1.xmp"); dir.file("IMG_1.CR3.XMP"); dir.file("IMG_10.xmp"); dir.file("IMG_1.AAE")
        let sidecars = MediaScanner.sidecars(of: raw)
        let names = sidecars.map { $0.name(forMainFileNamed: "NEW.cr3") }.sorted()
        #expect(names == ["NEW.AAE", "NEW.cr3.XMP", "NEW.xmp"])
    }
}
