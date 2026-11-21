import Foundation

struct EXIFData {
    /// Wall-clock capture time exactly as recorded by the camera (EXIF has no time zone),
    /// or the file date converted to local wall-clock time as a fallback.
    /// Stored as components so formatting never depends on the user's calendar, locale or time zone.
    var captureDate: DateComponents?
    var make: String?
    var model: String?
    var lensModel: String?
    var iso: Int?
    var fileExtension: String = ""

    // Zero-padded date components (always Gregorian digits, independent of user locale)
    var year: String   { pad(captureDate?.year, 4) }
    var month: String  { pad(captureDate?.month, 2) }
    var day: String    { pad(captureDate?.day, 2) }
    var hour: String   { pad(captureDate?.hour, 2) }
    var minute: String { pad(captureDate?.minute, 2) }
    var second: String { pad(captureDate?.second, 2) }

    /// Sortable key used to order photos chronologically (e.g. for counter assignment).
    var sortKey: String { year + month + day + hour + minute + second }

    private func pad(_ value: Int?, _ width: Int) -> String {
        let s = String(value ?? 0)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }
}
