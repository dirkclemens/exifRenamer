import Foundation
import ImageIO

nonisolated struct EXIFReader {   // thread-safe, used from background tasks
    static func read(url: URL) -> EXIFData {
        var data = EXIFData()
        data.fileExtension = url.pathExtension.lowercased()

        // Don't decode/cache pixel data — we only need metadata.
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, options) as? [String: Any]
        else {
            data.captureDate = fileDate(of: url)
            return data
        }

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        data.make      = clean(tiff?[kCGImagePropertyTIFFMake  as String] as? String)
        data.model     = clean(tiff?[kCGImagePropertyTIFFModel as String] as? String)
        data.lensModel = clean(exif?[kCGImagePropertyExifLensModel as String] as? String)

        if let isoArr = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber] {
            data.iso = isoArr.first?.intValue
        }

        // Prefer the capture time, then the digitized time, then the TIFF modify time.
        let candidates: [String?] = [
            exif?[kCGImagePropertyExifDateTimeOriginal  as String] as? String,
            exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String,
            tiff?[kCGImagePropertyTIFFDateTime          as String] as? String,
        ]
        data.captureDate = candidates.lazy.compactMap { $0.flatMap { Self.parseEXIFDate($0) } }.first
            ?? fileDate(of: url)

        let subsecKeys = [kCGImagePropertyExifSubsecTimeOriginal, kCGImagePropertyExifSubsecTimeDigitized, kCGImagePropertyExifSubsecTime]
        data.milliseconds = subsecKeys.lazy
            .compactMap { exif?[$0 as String] as? String }
            .compactMap { Self.parseSubseconds($0) }
            .first
        return data
    }

    /// SubSecTime is a string of fractional-second digits ("5" = .5 s, "07" = .07 s, "123" = .123 s).
    /// Normalized to milliseconds (0…999).
    static func parseSubseconds(_ string: String) -> Int? {
        let digits = string.trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let ms = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return Int(ms)
    }

    /// Parses `"YYYY:MM:DD HH:MM:SS"` (also tolerates `-` as date separator) without a
    /// DateFormatter, so the result is independent of the user's calendar, locale and
    /// 12/24-hour setting. Returns nil for empty/zeroed values like `"0000:00:00 00:00:00"`.
    static func parseEXIFDate(_ string: String) -> DateComponents? {
        let parts = string
            .split(whereSeparator: { !$0.isNumber })
            .prefix(6)
            .compactMap { Int($0) }
        guard parts.count == 6 else { return nil }
        let (y, mo, d, h, mi, s) = (parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
        guard y > 0, (1...12).contains(mo), (1...31).contains(d),
              (0...23).contains(h), (0...59).contains(mi), (0...60).contains(s)
        else { return nil }
        return DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
    }

    /// Fallback: file modification date (survives copying from a memory card, unlike the creation date),
    /// expressed as local wall-clock time in the Gregorian calendar.
    private static func fileDate(of url: URL) -> DateComponents? {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    /// EXIF strings are often padded with spaces or NUL bytes ("Canon ", "NIKON CORPORATION\0").
    private static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }
}
