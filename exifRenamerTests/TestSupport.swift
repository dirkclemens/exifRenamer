import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import exifRenamer

/// Grants folder access without any dialog.
final class GrantAllAccess: FolderAccessing {
    var requested: [URL] = []
    func requestAccess(to directory: URL) -> Bool { requested.append(directory); return true }
    func startAccessing(directory: URL) -> (URL?, Bool) { (nil, false) }
    func stopAccessing(url: URL) {}
}

/// Denies every folder access request.
final class DenyAllAccess: FolderAccessing {
    func requestAccess(to directory: URL) -> Bool { false }
    func startAccessing(directory: URL) -> (URL?, Bool) { (nil, false) }
    func stopAccessing(url: URL) {}
}

/// A fresh temporary folder, removed on deinit.
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exifRenamerTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ name: String, _ content: String = "x") -> URL {
        let u = url.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func read(_ name: String) -> String? {
        try? String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
    }

    /// File names directly in the folder (or a subfolder), sorted.
    func names(_ sub: String = "") -> [String] {
        let dir = sub.isEmpty ? url : url.appendingPathComponent(sub)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0 != ".DS_Store" }.sorted()
    }

    /// Writes a tiny JPEG with the given EXIF/TIFF metadata.
    @discardableResult
    func jpeg(_ name: String, exif: [CFString: Any], tiff: [CFString: Any] = [:]) -> URL {
        let u = url.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
        return u
    }
}

func exif(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, _ s: Int = 0, ext: String = "jpg") -> EXIFData {
    var e = EXIFData()
    e.captureDate = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
    e.fileExtension = ext
    return e
}

@MainActor
func photo(_ url: URL, _ data: EXIFData? = nil, name: String? = nil) -> Photo {
    let p = Photo(url: url)
    p.exifData = data
    if let name { p.proposedName = name }
    return p
}
