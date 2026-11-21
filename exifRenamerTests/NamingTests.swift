import Foundation
import Testing
@testable import exifRenamer

@MainActor
struct NamingTests {
    func vm(format: String) -> AppViewModel {
        let vm = AppViewModel()
        let style = NamingStyle(name: "Test", formatString: format)
        vm.styles = [style]
        vm.selectedStyleID = style.id
        return vm
    }

    @Test func uniqueNamesHaveNoCounter() {
        let dir = TempDir()
        let m = vm(format: "%Y%M%D_%h%m%s%C.%F")
        m.photos = [photo(dir.file("a.jpg"), exif(2026, 1, 1, 10)), photo(dir.file("b.jpg"), exif(2026, 1, 1, 11))]
        m.refreshProposedNames()
        #expect(m.photos.map(\.proposedName) == ["20260101_100000.jpg", "20260101_110000.jpg"])
    }

    @Test func collisionsAreNumberedChronologically() {
        let dir = TempDir()
        let m = vm(format: "%Y%M%D%C.%F")
        var late = exif(2026, 1, 1, 18); late.milliseconds = 0
        let early = exif(2026, 1, 1, 8)
        m.photos = [photo(dir.file("z.jpg"), late), photo(dir.file("y.jpg"), early)]
        m.refreshProposedNames()
        #expect(m.photos.map(\.proposedName) == ["20260101_02.jpg", "20260101_01.jpg"])
    }

    @Test func formatWithoutCounterStillYieldsUniqueNames() {
        let dir = TempDir()
        let m = vm(format: "%Y%M%D.%F")
        m.photos = [photo(dir.file("a.jpg"), exif(2026, 1, 1, 8)), photo(dir.file("b.jpg"), exif(2026, 1, 1, 9))]
        m.refreshProposedNames()
        #expect(m.photos.map(\.proposedName) == ["20260101_01.jpg", "20260101_02.jpg"])
    }

    @Test func rawJpegPairsShareTheirCounter() {
        let dir = TempDir()
        let m = vm(format: "%Y%M%D_%h%m%s%C.%F")
        let t = exif(2026, 5, 1, 12)
        // IMG_1 is a RAW+JPG pair, IMG_2 only a JPG — all taken in the same second
        m.photos = [
            photo(dir.file("IMG_1.CR3"), { var e = t; e.fileExtension = "cr3"; return e }()),
            photo(dir.file("IMG_1.JPG"), t),
            photo(dir.file("IMG_2.JPG"), t),
        ]
        m.refreshProposedNames()
        #expect(m.photos.map(\.proposedName) == ["20260501_120000_01.cr3", "20260501_120000_01.jpg", "20260501_120000_02.jpg"])
    }

    @Test func singlePairNeedsNoCounter() {
        let dir = TempDir()
        let m = vm(format: "%Y%M%D%C.%F")
        let t = exif(2026, 5, 1)
        m.photos = [photo(dir.file("IMG_1.CR3"), { var e = t; e.fileExtension = "cr3"; return e }()), photo(dir.file("IMG_1.JPG"), t)]
        m.refreshProposedNames()
        #expect(m.photos.map(\.proposedName) == ["20260501.cr3", "20260501.jpg"])
    }

    @Test func removingAPhotoDropsObsoleteCounters() {
        let dir = TempDir()
        let m = vm(format: "%Y%C.%F")
        m.photos = [photo(dir.file("a.jpg"), exif(2026, 1, 1, 8)), photo(dir.file("b.jpg"), exif(2026, 1, 1, 9))]
        m.refreshProposedNames()
        m.removePhotos(ids: [m.photos[1].id])
        #expect(m.photos.map(\.proposedName) == ["2026.jpg"])
    }

    @Test func customFolderWithoutFolderBlocksRename() {
        let dir = TempDir()
        let m = vm(format: "%Y.%F")
        m.photos = [photo(dir.file("a.jpg"), exif(2026, 1, 1))]
        m.refreshProposedNames()
        #expect(m.canRename)
        m.useCustomFolder = true
        #expect(!m.canRename)
        if case .sameFolder = m.outputMode {} else { Issue.record("must not fall back to a custom folder") }
    }
}
