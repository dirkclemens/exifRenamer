import Foundation
import ImageIO
import Testing
@testable import exifRenamer

@MainActor
struct EXIFReaderTests {
    @Test(arguments: [
        ("2026:04:26 14:30:05", DateComponents(year: 2026, month: 4, day: 26, hour: 14, minute: 30, second: 5)),
        ("2026-04-26 14:30:05", DateComponents(year: 2026, month: 4, day: 26, hour: 14, minute: 30, second: 5)),
    ])
    func parsesEXIFDates(_ input: String, _ expected: DateComponents) {
        #expect(EXIFReader.parseEXIFDate(input) == expected)
    }

    @Test(arguments: ["0000:00:00 00:00:00", "    :  :     :  :  ", "", "2026:13:01 00:00:00", "garbage"])
    func rejectsInvalidDates(_ input: String) {
        #expect(EXIFReader.parseEXIFDate(input) == nil)
    }

    @Test(arguments: [("5", 500), ("07", 70), ("123", 123), ("1234", 123), (" 42 ", 420), ("", nil), ("x", nil)] as [(String, Int?)])
    func normalizesSubseconds(_ input: String, _ expected: Int?) {
        #expect(EXIFReader.parseSubseconds(input) == expected)
    }

    @Test func readsMetadataFromJPEG() throws {
        let dir = TempDir()
        let url = dir.jpeg("IMG_0001.JPG", exif: [
            kCGImagePropertyExifDateTimeOriginal: "2025:12:24 18:05:09",
            kCGImagePropertyExifSubsecTimeOriginal: "25",
            kCGImagePropertyExifISOSpeedRatings: [800],
            kCGImagePropertyExifLensModel: "RF 50mm F1.8 STM",
        ], tiff: [
            kCGImagePropertyTIFFMake: "Canon ",
            kCGImagePropertyTIFFModel: "EOS R6",
        ])
        let data = EXIFReader.read(url: url)
        #expect(data.year + data.month + data.day == "20251224")
        #expect(data.hour + data.minute + data.second == "180509")
        #expect(data.milliseconds == 250)
        #expect(data.iso == 800)
        #expect(data.make == "Canon")      // trailing space trimmed
        #expect(data.model == "EOS R6")
        #expect(data.lensModel == "RF 50mm F1.8 STM")
        #expect(data.fileExtension == "jpg")
    }

    @Test func fallsBackToModificationDate() throws {
        let dir = TempDir()
        let url = dir.file("notes.jpg", "not an image")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let date = cal.date(from: DateComponents(year: 2020, month: 2, day: 29, hour: 7, minute: 8, second: 9))!
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let data = EXIFReader.read(url: url)
        #expect(data.year + data.month + data.day + data.hour + data.minute + data.second == "20200229070809")
    }
}
