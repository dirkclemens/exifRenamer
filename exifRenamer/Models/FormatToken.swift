import Foundation

enum FormatToken: String, CaseIterable {
    case year      = "%Y"
    case month     = "%M"
    case day       = "%D"
    case hour      = "%h"
    case minute    = "%m"
    case second    = "%s"
    case counter   = "%C"
    case ext       = "%F"
    case make      = "%make"
    case model     = "%model"
    case iso       = "%iso"
    case lens      = "%lens"
    
    // New Video & Utility Tokens
    case res       = "%res"
    case resLabel  = "%resLabel"
    case fps       = "%fps"
    case origName  = "%name"

    var description: String {
        switch self {
        case .year:     return "Year (4-digit)"
        case .month:    return "Month"
        case .day:      return "Day"
        case .hour:     return "Hour (24h)"
        case .minute:   return "Minute"
        case .second:   return "Second"
        case .counter:  return "Counter (when duplicate)"
        case .ext:      return "File extension"
        case .make:     return "Camera make"
        case .model:    return "Camera model"
        case .iso:      return "ISO"
        case .lens:     return "Lens model"
            
        case .res:      return "Resolution (e.g., 1920x1080)"
        case .resLabel: return "Resolution Label (e.g., 1080p, 4K)"
        case .fps:      return "Frame Rate (e.g., 60fps)"
        case .origName: return "Original Filename"
        }
    }
}
