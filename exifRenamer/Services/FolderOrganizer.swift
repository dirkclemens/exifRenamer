import Foundation

struct FolderOrganizer {
    /// Returns (or creates) the destination folder URL for a photo.
    static func resolvedFolder(for photo: Photo, style: NamingStyle, baseDestination: URL) throws -> URL {
        guard let folderFormat = style.folderFormatString, !folderFormat.isEmpty else {
            return baseDestination
        }
        let exif = photo.exifData ?? EXIFData()
        let relative = FormatEngine.resolve(format: folderFormat, exif: exif, counter: nil)
        let folderURL = relative.components(separatedBy: "/")
            .reduce(baseDestination) { $0.appendingPathComponent($1) }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}
