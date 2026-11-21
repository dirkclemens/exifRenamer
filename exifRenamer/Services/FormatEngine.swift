import Foundation

struct FormatEngine {
    /// Tokens ordered longest first so `%make` wins over `%m`, `%model` over `%m`, etc.
    private static let tokensByLength: [FormatToken] =
        FormatToken.allCases.sorted { $0.rawValue.count > $1.rawValue.count }

    /// Resolve a format string against EXIF data. Pass counter=nil to drop %C.
    /// Single-pass scan: substituted values are never re-interpreted as tokens.
    /// The result is raw — use `fileName(...)` or `folderComponents(...)` for paths.
    static func resolve(format: String, exif: EXIFData, counter: Int?) -> String {
        var result = ""
        var rest = Substring(format)
        while let pct = rest.firstIndex(of: "%") {
            result += rest[..<pct]
            rest = rest[pct...]
            if let token = tokensByLength.first(where: { rest.hasPrefix($0.rawValue) }) {
                result += value(for: token, exif: exif, counter: counter)
                rest = rest.dropFirst(token.rawValue.count)
            } else {
                result += "%"            // unknown token: keep literally
                rest = rest.dropFirst()
            }
        }
        result += rest
        return result
    }

    /// Resolve a *file name*: path separators and characters that are illegal or
    /// troublesome in Finder are replaced, leading/trailing dots/spaces are removed
    /// (no hidden files, no `name.` when the extension is empty).
    static func fileName(format: String, exif: EXIFData, counter: Int?) -> String {
        let raw = resolve(format: format, exif: exif, counter: counter)
        return sanitize(raw).trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
    }

    /// Resolve a *folder pattern* into safe relative path components.
    /// `/` separates folders; empty, `.` and `..` components are dropped so a pattern
    /// can never escape the destination folder.
    static func folderComponents(format: String, exif: EXIFData) -> [String] {
        resolve(format: format, exif: exif, counter: nil)
            .split(separator: "/")
            .map { sanitize(String($0)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// True if the format contains the %C counter token.
    static func containsCounter(_ format: String) -> Bool {
        format.contains(FormatToken.counter.rawValue)
    }

    /// Live preview (no counter)
    static func preview(format: String, exif: EXIFData) -> String {
        fileName(format: format, exif: exif, counter: nil)
    }

    static func folderPreview(format: String, exif: EXIFData) -> String {
        folderComponents(format: format, exif: exif).joined(separator: "/")
    }

    /// Formats a counter the same way %C does (used when a collision has to be resolved
    /// for a format without %C).
    static func counterSuffix(_ n: Int) -> String { String(format: "_%02d", n) }

    private static func value(for token: FormatToken, exif: EXIFData, counter: Int?) -> String {
        switch token {
        case .make:    return sanitize(exif.make ?? "unknown")
        case .model:   return sanitize(exif.model ?? "unknown")
        case .lens:    return sanitize(exif.lensModel ?? "unknown")
        case .iso:     return exif.iso.map(String.init) ?? "0"
        case .year:    return exif.year
        case .month:   return exif.month
        case .day:     return exif.day
        case .hour:    return exif.hour
        case .minute:  return exif.minute
        case .second:  return exif.second
        case .millisecond: return exif.millisecond
        case .ext:     return exif.fileExtension
        case .counter: return counter.map { counterSuffix($0) } ?? ""
        }
    }

    private static let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)

    private static func sanitize(_ s: String) -> String {
        s.components(separatedBy: illegal).joined(separator: "_")
    }
}
