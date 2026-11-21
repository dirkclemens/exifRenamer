import Foundation
import Testing
@testable import exifRenamer

@MainActor
struct FormatEngineTests {
    let sample: EXIFData = {
        var e = exif(2026, 4, 6, 9, 5, 3, ext: "cr3")
        e.make = "Canon"; e.model = "EOS/R5"; e.lensModel = "RF 24-70mm F2.8"
        e.iso = 400; e.milliseconds = 70
        return e
    }()

    @Test func dateTokensArePadded() {
        #expect(FormatEngine.fileName(format: "%Y%M%D_%h%m%s%C.%F", exif: sample, counter: nil) == "20260406_090503.cr3")
    }

    @Test func longestTokenWinsAndValuesAreSanitized() {
        #expect(FormatEngine.fileName(format: "%make_%model_%m_%iso_%lens", exif: sample, counter: nil)
                == "Canon_EOS_R5_05_400_RF 24-70mm F2.8")
    }

    @Test func millisecondsToken() {
        #expect(FormatEngine.fileName(format: "%h%m%s%ms", exif: sample, counter: nil) == "090503070")
    }

    @Test func counterOnlyWhenGiven() {
        #expect(FormatEngine.fileName(format: "%Y%C.%F", exif: sample, counter: 3) == "2026_03.cr3")
        #expect(FormatEngine.fileName(format: "%Y%C.%F", exif: sample, counter: nil) == "2026.cr3")
    }

    @Test func substitutedValuesAreNotReinterpreted() {
        var e = sample; e.model = "X%Y"
        #expect(FormatEngine.fileName(format: "%model", exif: e, counter: nil) == "X%Y")
    }

    @Test func unknownPercentIsKept() {
        #expect(FormatEngine.fileName(format: "100%_%Y", exif: sample, counter: nil) == "100%_2026")
    }

    @Test func fileNameNeverContainsPathSeparators() {
        #expect(FormatEngine.fileName(format: "%Y/%M:%D.%F", exif: sample, counter: nil) == "2026_04_06.cr3")
    }

    @Test func missingDateAndExtension() {
        var e = EXIFData(); e.fileExtension = ""
        #expect(FormatEngine.fileName(format: "%Y-%M-%D.%F", exif: e, counter: nil) == "0000-00-00")
        #expect(FormatEngine.fileName(format: "%make", exif: e, counter: nil) == "unknown")
    }

    @Test func folderPatternCannotEscape() {
        #expect(FormatEngine.folderComponents(format: "../%Y/./%Y-%M-%D//..", exif: sample) == ["2026", "2026-04-06"])
    }
}
