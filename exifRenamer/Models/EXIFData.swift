import Foundation

struct EXIFData {
    var dateTimeOriginal: Date?
    var make: String?
    var model: String?
    var lensModel: String?
    var iso: Int?
    var fileExtension: String = ""
    var raw: [String: Any] = [:]

    // Computed date components
    var year: String   { component("yyyy") }
    var month: String  { component("MM") }
    var day: String    { component("dd") }
    var hour: String   { component("HH") }
    var minute: String { component("mm") }
    var second: String { component("ss") }

    private func component(_ format: String) -> String {
        guard let date = dateTimeOriginal else { return "0000" }
        let f = DateFormatter(); f.dateFormat = format
        return f.string(from: date)
    }
}
