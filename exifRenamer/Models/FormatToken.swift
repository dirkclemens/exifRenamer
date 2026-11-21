import Foundation

enum FormatToken: String, CaseIterable {
    case year      = "%Y"
    case month     = "%M"
    case day       = "%D"
    case hour      = "%h"
    case minute    = "%m"
    case second    = "%s"
    case millisecond = "%ms"
    case counter   = "%C"
    case ext       = "%F"
    case make      = "%make"
    case model     = "%model"
    case iso       = "%iso"
    case lens      = "%lens"

    var description: String {
        switch self {
        case .year:    return String(localized: "Year (4-digit)")
        case .month:   return String(localized: "Month")
        case .day:     return String(localized: "Day")
        case .hour:    return String(localized: "Hour (24h)")
        case .minute:  return String(localized: "Minute")
        case .second:  return String(localized: "Second")
        case .millisecond: return String(localized: "Milliseconds")
        case .counter: return String(localized: "Counter (when duplicate)")
        case .ext:     return String(localized: "File extension")
        case .make:    return String(localized: "Camera make")
        case .model:   return String(localized: "Camera model")
        case .iso:     return String(localized: "ISO")
        case .lens:    return String(localized: "Lens model")
        }
    }
}
