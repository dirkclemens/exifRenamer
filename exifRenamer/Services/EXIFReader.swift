import Foundation
import ImageIO

struct EXIFReader {
    static func read(url: URL) -> EXIFData {
        var data = EXIFData()
        data.fileExtension = url.pathExtension.lowercased()

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else {
            data.dateTimeOriginal = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return data
        }
        data.raw = props

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        data.make      = tiff?[kCGImagePropertyTIFFMake  as String] as? String
        data.model     = tiff?[kCGImagePropertyTIFFModel as String] as? String
        data.lensModel = exif?[kCGImagePropertyExifLensModel as String] as? String

        if let isoArr = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] {
            data.iso = isoArr.first
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let dtStr = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            data.dateTimeOriginal = fmt.date(from: dtStr)
        }
        if data.dateTimeOriginal == nil {
            data.dateTimeOriginal = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return data
    }
}
