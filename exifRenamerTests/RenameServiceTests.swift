import Foundation
import Testing
@testable import exifRenamer

@MainActor
struct RenameServiceTests {
    let style = NamingStyle(name: "t", formatString: "%Y.%F")

    func run(_ photos: [Photo], mode: OutputMode = .sameFolder, strategy: ConflictStrategy = .autoNumber,
             folders: Bool = false, style: NamingStyle? = nil, sidecars: Bool = true,
             access: FolderAccessing? = nil) async -> RenameBatch {
        await RenameService.process(photos: photos, style: style ?? self.style, outputMode: mode,
                                    conflictStrategy: strategy, createFolders: folders,
                                    includeSidecars: sidecars, access: access ?? GrantAllAccess())
    }

    @Test func renamesInPlace() async {
        let dir = TempDir()
        let batch = await run([photo(dir.file("IMG_1.jpg", "A"), name: "new.jpg")])
        #expect(dir.names() == ["new.jpg"])
        #expect(dir.read("new.jpg") == "A")
        if case .success = batch.results[0] {} else { Issue.record("expected success") }
    }

    @Test func overwriteOntoItselfKeepsTheFile() async {
        let dir = TempDir()
        let batch = await run([photo(dir.file("same.jpg", "ONE"), name: "same.jpg")], strategy: .overwrite)
        #expect(dir.read("same.jpg") == "ONE")
        if case .skipped = batch.results[0] {} else { Issue.record("expected skipped") }
    }

    @Test func caseOnlyRename() async {
        let dir = TempDir()
        _ = await run([photo(dir.file("lower.jpg", "C"), name: "LOWER.jpg")], strategy: .overwrite)
        #expect(dir.names() == ["LOWER.jpg"])
        #expect(dir.read("LOWER.jpg") == "C")
    }

    @Test func chainRenameNeverOverwritesPendingSources() async {
        let dir = TempDir()
        let a = photo(dir.file("a.jpg", "A"), name: "b.jpg")
        let b = photo(dir.file("b.jpg", "B"), name: "c.jpg")
        _ = await run([a, b], strategy: .overwrite)
        let contents = Set(dir.names().compactMap(dir.read))
        #expect(contents == ["A", "B"])
    }

    @Test func overwriteMovesReplacedFileToTrash() async {
        let dir = TempDir()
        dir.file("taken.jpg", "OLD")
        let batch = await run([photo(dir.file("x.jpg", "NEW"), name: "taken.jpg")], strategy: .overwrite)
        #expect(dir.read("taken.jpg") == "NEW")
        #expect(batch.operations.contains { $0.kind == .trash || $0.kind == .delete })
    }

    @Test func autoNumberAndSkip() async {
        let dir = TempDir()
        dir.file("taken.jpg", "T")
        _ = await run([photo(dir.file("x.jpg", "X"), name: "taken.jpg")], strategy: .autoNumber)
        #expect(dir.read("taken_01.jpg") == "X")
        let skipped = await run([photo(dir.file("y.jpg", "Y"), name: "taken.jpg")], strategy: .skip)
        #expect(dir.read("y.jpg") == "Y")
        if case .skipped = skipped.results[0] {} else { Issue.record("expected skipped") }
    }

    @Test func deniedFolderAccessFailsWithoutTouchingFiles() async {
        let dir = TempDir()
        let batch = await run([photo(dir.file("a.jpg"), name: "b.jpg")], access: DenyAllAccess())
        #expect(dir.names() == ["a.jpg"])
        if case .failed = batch.results[0] {} else { Issue.record("expected failure") }
    }

    @Test func subfoldersAreCopiesAndRecorded() async {
        let dir = TempDir()
        var s = style; s.folderFormatString = "%Y/%M"
        let p = photo(dir.file("a.jpg", "S"), exif(2025, 1, 2), name: "n.jpg")
        let batch = await run([p], folders: true, style: s)
        #expect(dir.read("2025/01/n.jpg") == "S")
        #expect(dir.read("a.jpg") == "S")
        #expect(batch.operations.filter { $0.kind == .createFolder }.count == 2)
    }

    @Test func copiesToCustomFolder() async {
        let src = TempDir(), dst = TempDir()
        let access = GrantAllAccess()
        _ = await run([photo(src.file("a.jpg", "A"), name: "b.jpg")], mode: .customFolder(dst.url), access: access)
        #expect(src.names() == ["a.jpg"])
        #expect(dst.read("b.jpg") == "A")
        #expect(access.requested.isEmpty)   // copying needs no source-folder write access
    }

    @Test func sidecarsFollowTheirPhoto() async {
        let dir = TempDir()
        dir.file("IMG_1.xmp", "X1"); dir.file("IMG_1.CR3.xmp", "X2"); dir.file("IMG_1.AAE", "A")
        _ = await run([photo(dir.file("IMG_1.CR3", "R"), name: "2026.cr3")])
        #expect(dir.names() == ["2026.AAE", "2026.cr3", "2026.cr3.xmp", "2026.xmp"])
    }

    @Test func sidecarsCanBeDisabled() async {
        let dir = TempDir()
        dir.file("IMG_1.xmp", "X1")
        _ = await run([photo(dir.file("IMG_1.CR3", "R"), name: "2026.cr3")], sidecars: false)
        #expect(dir.names() == ["2026.cr3", "IMG_1.xmp"])
    }

    @Test func undoRestoresMovesSidecarsAndFolders() async {
        let dir = TempDir()
        dir.file("IMG_1.xmp", "X")
        let moved = await run([photo(dir.file("IMG_1.jpg", "M"), name: "new.jpg")])
        #expect(dir.names() == ["new.jpg", "new.xmp"])
        let outcome = await RenameService.undo(moved.operations, access: GrantAllAccess())
        #expect(outcome.failed == 0)
        #expect(dir.names() == ["IMG_1.jpg", "IMG_1.xmp"])

        var s = style; s.folderFormatString = "%Y"
        let copied = await run([photo(dir.file("IMG_1.jpg"), exif(2024, 1, 1), name: "c.jpg")], folders: true, style: s)
        #expect(dir.exists("2024/c.jpg"))
        _ = await RenameService.undo(copied.operations, access: GrantAllAccess())
        #expect(!dir.exists("2024"))
        #expect(dir.names() == ["IMG_1.jpg", "IMG_1.xmp"])
    }
}
