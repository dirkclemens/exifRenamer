import Foundation

struct FolderOrganizer {
    /// Computes the destination folder for a photo (pure, no file system access).
    static func folder(for photo: Photo, style: NamingStyle, baseDestination: URL) -> URL {
        guard let folderFormat = style.folderFormatString, !folderFormat.isEmpty else {
            return baseDestination
        }
        let components = FormatEngine.folderComponents(format: folderFormat, exif: photo.exifData ?? EXIFData())
        return components.reduce(baseDestination) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// Returns the destination folder URL for a photo, creating it if needed.
    /// Call only while write access to `baseDestination` is held.
    static func resolvedFolder(for photo: Photo, style: NamingStyle, baseDestination: URL) throws -> URL {
        let url = folder(for: photo, style: style, baseDestination: baseDestination)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
