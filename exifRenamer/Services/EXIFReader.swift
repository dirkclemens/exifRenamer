import Foundation
import ImageIO
import AVFoundation

struct EXIFReader {
    static func read(url: URL) async -> EXIFData {
        var data = EXIFData()
        let ext = url.pathExtension.lowercased()
        data.fileExtension = ext

        let videoExts = Set(["mp4", "mov", "m4v", "avi", "mkv", "hevc", "mts", "m2ts", "3gp"])
        
        if videoExts.contains(ext) {
            let asset = AVURLAsset(url: url)
            
            // Extract video tracks for resolution and framerate asynchronously
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                if let naturalSize = try? await track.load(.naturalSize) {
                    let width = Int(abs(naturalSize.width))
                    let height = Int(abs(naturalSize.height))
                    data.resolution = "\(width)x\(height)"
                    
                    let minDim = min(width, height)
                    if minDim >= 2160 { data.resolutionLabel = "4K" }
                    else if minDim >= 1080 { data.resolutionLabel = "1080p" }
                    else if minDim >= 720 { data.resolutionLabel = "720p" }
                    else { data.resolutionLabel = "SD" }
                }
                
                if let nominalFrameRate = try? await track.load(.nominalFrameRate), nominalFrameRate > 0 {
                    data.frameRate = "\(Int(round(nominalFrameRate)))fps"
                }
            }
            
            let metadata = (try? await asset.load(.metadata)) ?? []

            // Extract creation date from AVAsset metadata asynchronously
            if let creationDateItem = try? await asset.load(.creationDate),
               let date = try? await creationDateItem.load(.dateValue) {
                data.dateTimeOriginal = date
            } else if let creationDateItem = metadata.first(where: { $0.commonKey == .commonKeyCreationDate }),
                      let dateString = try? await creationDateItem.load(.stringValue) {
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "en_US_POSIX")
                fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let d = fmt.date(from: dateString) {
                    data.dateTimeOriginal = d
                }
            }

            // Extract Make and Model if the camera embedded them into the video
            for item in metadata {
                if item.commonKey == .commonKeyMake {
                    data.make = try? await item.load(.stringValue)
                } else if item.commonKey == .commonKeyModel {
                    data.model = try? await item.load(.stringValue)
                }
            }

            // Fallback to file modification date if AVFoundation couldn't find an embedded date
            if data.dateTimeOriginal == nil {
                data.dateTimeOriginal = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
            
            return data
        }

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
