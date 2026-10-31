import Foundation

struct FormatEngine {
    /// Resolve a format string against EXIF data. Pass counter=nil to skip %C.
    /// Added `originalName` parameter with a default fallback to avoid breaking existing calls.
    static func resolve(format: String, exif: EXIFData, originalName: String = "OriginalName", counter: Int?) -> String {
        // Longest tokens first to avoid partial matches (e.g., %resLabel before %res, %model before %m)
        let tokens: [(String, String)] = [
            ("%make",     sanitize(exif.make  ?? "unknown")),
            ("%model",    sanitize(exif.model ?? "unknown")),
            ("%lens",     sanitize(exif.lensModel ?? "unknown")),
            ("%iso",      exif.iso.map(String.init) ?? "0"),
            
            // Video & Utility Tokens
            ("%resLabel", sanitize(exif.resolutionLabel ?? "unknown")),
            ("%res",      sanitize(exif.resolution ?? "unknown")),
            ("%fps",      sanitize(exif.frameRate ?? "unknown")),
            ("%name",     sanitize(originalName)),
            
            // Standard Date & System Tokens
            ("%Y",        exif.year),
            ("%M",        exif.month),
            ("%D",        exif.day),
            ("%h",        exif.hour),
            ("%m",        exif.minute),
            ("%s",        exif.second),
            ("%F",        exif.fileExtension),
            ("%C",        counter.map { String(format: "_%02d", $0) } ?? ""),
        ]
        var result = format
        for (token, value) in tokens {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }

    /// Live preview with placeholder counter = 1
    static func preview(format: String, exif: EXIFData, originalName: String = "IMG_0001") -> String {
        resolve(format: format, exif: exif, originalName: originalName, counter: nil)
    }

    private static func sanitize(_ s: String) -> String {
        s.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined(separator: "_")
    }
}
