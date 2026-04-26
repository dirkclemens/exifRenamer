import Foundation

struct NamingStyle: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var formatString: String          // e.g. "%Y_%M%D_%h%m%s%C.%F"
    var folderFormatString: String?   // e.g. "%Y/%Y-%M-%D"
    var isBuiltIn: Bool = false

    static let defaults: [NamingStyle] = [
        NamingStyle(name: "Date+Time", formatString: "%Y%M%D_%h%m%s%C.%F", isBuiltIn: true),
        NamingStyle(name: "Date only", formatString: "%Y-%M-%D%C.%F", isBuiltIn: true),
        NamingStyle(name: "Camera+Date", formatString: "%make_%model_%Y%M%D_%h%m%s%C.%F", isBuiltIn: true),
    ]
}
