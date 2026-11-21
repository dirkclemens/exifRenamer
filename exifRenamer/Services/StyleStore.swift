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
        if let data = try? Data(contentsOf: fileURL) {
            do {
                let styles = try JSONDecoder().decode([NamingStyle].self, from: data)
                if !styles.isEmpty { return styles }
            } catch {
                // Never silently overwrite a file we can't read — keep a copy of the user's styles.
                let backup = fileURL.deletingPathExtension()
                    .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                DebugLog.error("StyleStore: could not decode styles.json (\(error)); backup at \(backup.path)")
            }
        }
        // First launch (or unreadable file) — save defaults
        let defaults = NamingStyle.defaults
        save(defaults)
        return defaults
    }

    func save(_ styles: [NamingStyle]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(styles).write(to: fileURL, options: .atomic)
        } catch {
            DebugLog.error("StyleStore: saving styles failed: \(error.localizedDescription)")
        }
    }
}
