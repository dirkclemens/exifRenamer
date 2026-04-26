import Foundation

class StyleStore {
    static let shared = StyleStore()
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("exifRenamer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("styles.json")
    }

    func load() -> [NamingStyle] {
        if let data = try? Data(contentsOf: fileURL),
           let styles = try? JSONDecoder().decode([NamingStyle].self, from: data) {
            return styles
        }
        // First launch — save defaults
        let defaults = NamingStyle.defaults
        save(defaults)
        return defaults
    }

    func save(_ styles: [NamingStyle]) {
        guard let data = try? JSONEncoder().encode(styles) else { return }
        try? data.write(to: fileURL)
    }
}
