import Foundation
import UniformTypeIdentifiers

/// Finds image files in dropped/chosen items. Thread-safe; runs off the main thread.
nonisolated enum MediaScanner {
    /// Extensions treated as sidecar files that belong to a photo (Lightroom/Capture One XMP, Apple Photos edits).
    static let sidecarExtensions: Set<String> = ["xmp", "aae"]

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    /// Expands folders (recursively, skipping hidden files and packages) and keeps image files,
    /// sorted by path.
    static func imageFiles(in urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            if isDirectory(url) {
                guard let e = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let file as URL in e where isImage(file) {
                    result.append(file)
                }
            } else if isImage(url) {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Uses the system type database, so every RAW format macOS knows (ORF, PEF, SRW, …),
    /// HEIF, WebP, AVIF etc. is accepted — not just a hard-coded extension list.
    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Sidecar files next to `file`: both `IMG_0001.xmp` (Lightroom style) and
    /// `IMG_0001.CR3.xmp` (darktable style). Requires read access to the folder;
    /// returns an empty list otherwise.
    static func sidecars(of file: URL) -> [Sidecar] {
        let dir = file.deletingLastPathComponent()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        let fileName = file.lastPathComponent.lowercased()
        let stem = file.deletingPathExtension().lastPathComponent.lowercased()
        return names.compactMap { name in
            let ext = (name as NSString).pathExtension
            guard sidecarExtensions.contains(ext.lowercased()) else { return nil }
            let base = (name as NSString).deletingPathExtension.lowercased()
            if base == stem     { return Sidecar(url: dir.appendingPathComponent(name), ext: ext, keepsMainExtension: false) }
            if base == fileName { return Sidecar(url: dir.appendingPathComponent(name), ext: ext, keepsMainExtension: true) }
            return nil
        }
    }

    struct Sidecar: Sendable {
        let url: URL
        /// Original extension, case preserved ("xmp", "XMP", "AAE")
        let ext: String
        /// true for `IMG.CR3.xmp` style (sidecar name = full main file name + extension)
        let keepsMainExtension: Bool

        /// Name of the sidecar for a main file renamed to `mainName`.
        func name(forMainFileNamed mainName: String) -> String {
            let base = keepsMainExtension ? mainName : (mainName as NSString).deletingPathExtension
            return base + "." + ext
        }
    }
}
