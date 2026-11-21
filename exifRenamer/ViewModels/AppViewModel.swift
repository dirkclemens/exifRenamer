import Foundation
import Observation

enum OutputMode {
    case sameFolder
    case customFolder(URL)
}

enum ConflictStrategy: String, CaseIterable, Codable {
    case skip, overwrite, autoNumber
    var label: String {
        switch self {
        case .skip:       return "Skip"
        case .overwrite:  return "Overwrite"
        case .autoNumber: return "Auto-number"
        }
    }

    static let defaultsKey = "defaultConflictStrategy"
}

@Observable
class AppViewModel {
    var photos: [Photo] = []
    var styles: [NamingStyle] = []
    var selectedStyleID: UUID?
    var useCustomFolder: Bool = false
    var customFolderURL: URL?
    var conflictStrategy: ConflictStrategy
    var createFolders: Bool = false
    var isProcessing: Bool = false
    var isLoading: Bool = false
    var loadedCount: Int = 0
    var loadingTotal: Int = 0
    var processedCount: Int = 0
    var processingTotal: Int = 0
    var errorMessage: String?
    /// Operations of the last rename batch that can be undone (empty = nothing to undo).
    private(set) var lastBatchOperations: [FileOperation] = []
    var includeSidecars: Bool = UserDefaults.standard.object(forKey: "includeSidecars") as? Bool ?? true {
        didSet { UserDefaults.standard.set(includeSidecars, forKey: "includeSidecars") }
    }

    var canUndo: Bool { !isProcessing && !lastBatchOperations.isEmpty }

    var selectedStyle: NamingStyle? {
        styles.first { $0.id == selectedStyleID }
    }

    var outputMode: OutputMode {
        if useCustomFolder, let url = customFolderURL { return .customFolder(url) }
        return .sameFolder
    }

    /// Subfolders are only created if the style actually has a folder pattern.
    var effectiveCreateFolders: Bool {
        createFolders && !(selectedStyle?.folderFormatString ?? "").isEmpty
    }

    var pendingPhotos: [Photo] {
        photos.filter { if case .renamed = $0.status { return false } else { return true } }
    }

    var canRename: Bool {
        !isProcessing
            && !isLoading
            && selectedStyle != nil
            && !pendingPhotos.isEmpty
            && !(useCustomFolder && customFolderURL == nil)
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: ConflictStrategy.defaultsKey) ?? ""
        conflictStrategy = ConflictStrategy(rawValue: raw) ?? .autoNumber
        styles = StyleStore.shared.load()
        selectedStyleID = styles.first?.id
    }

    /// Adds dropped/chosen files and folders. Folder scanning, bookmark creation and EXIF
    /// reading run in parallel off the main thread; the UI shows progress meanwhile.
    func addItems(urls: [URL]) async {
        // A dropped/chosen folder carries folder-level access — remember it so renaming
        // in place needs no extra permission dialog.
        for url in urls where MediaScanner.isDirectory(url) {
            FolderAccessManager.shared.registerGranted(directory: url)
        }
        let files = await Task.detached(priority: .userInitiated) { MediaScanner.imageFiles(in: urls) }.value

        var known = Set(photos.map { $0.url.standardizedFileURL })
        let newURLs = files.filter { known.insert($0.standardizedFileURL).inserted }
        DebugLog.info("addItems: items=\(urls.count), images=\(files.count), new=\(newURLs.count)")
        guard !newURLs.isEmpty else { return }

        isLoading = true
        loadedCount = 0
        loadingTotal = newURLs.count
        defer { isLoading = false }

        let loaded = await loadMetadata(newURLs)

        // Another add may have finished in the meantime — dedupe again.
        let present = Set(photos.map { $0.url.standardizedFileURL })
        let new = loaded
            .filter { !present.contains($0.url.standardizedFileURL) }
            .map { item -> Photo in
                let p = Photo(url: item.url, bookmarkData: item.bookmark)
                p.exifData = item.exif
                return p
            }
        photos.append(contentsOf: new)
        refreshProposedNames()
    }

    private struct LoadedItem: Sendable { let url: URL; let exif: EXIFData; let bookmark: Data? }

    /// Reads EXIF + creates bookmarks with bounded parallelism, keeping input order.
    private func loadMetadata(_ urls: [URL]) async -> [LoadedItem] {
        await withTaskGroup(of: (Int, LoadedItem).self) { group in
            var results = [LoadedItem?](repeating: nil, count: urls.count)
            let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
            var next = 0
            func enqueue() {
                let i = next, url = urls[i]
                group.addTask {
                    (i, LoadedItem(url: url, exif: EXIFReader.read(url: url), bookmark: Photo.makeBookmark(for: url)))
                }
                next += 1
            }
            while next < min(limit, urls.count) { enqueue() }
            for await (i, item) in group {
                results[i] = item
                loadedCount += 1
                if next < urls.count { enqueue() }
            }
            return results.compactMap { $0 }
        }
    }

    func removePhotos(ids: Set<UUID>) {
        photos.removeAll { ids.contains($0.id) }
        refreshProposedNames()   // counters may no longer be needed
    }

    func clearAll() {
        photos.removeAll()
        errorMessage = nil
    }

    /// Generates names for all photos. Names are guaranteed to be unique within the batch:
    /// colliding names get a counter (via %C, or appended before the extension if the
    /// format has no %C). Files of one shot — same folder and same original name, e.g.
    /// IMG_0001.CR3 + IMG_0001.JPG — form a pair and always get the same counter, so they
    /// stay together. Counters follow capture time, then original file name.
    func refreshProposedNames() {
        guard let style = selectedStyle else { return }
        let format = style.formatString
        let hasCounter = FormatEngine.containsCounter(format)

        func stem(_ name: String) -> String { (name as NSString).deletingPathExtension.lowercased() }
        func pairKey(_ p: Photo) -> String { p.url.deletingPathExtension().standardizedFileURL.path.lowercased() }

        // First pass — base names without counter
        var baseNames: [UUID: String] = [:]
        for photo in photos {
            baseNames[photo.id] = FormatEngine.fileName(format: format, exif: photo.exifData ?? EXIFData(), counter: nil)
        }

        // Which shots (pairs) end up with the same name stem? (case-insensitive, like APFS)
        var pairsPerStem: [String: [String: String]] = [:]   // stem → pairKey → earliest sort key
        for photo in photos {
            let s = stem(baseNames[photo.id] ?? photo.originalName)
            let sortKey = (photo.exifData?.sortKey ?? "") + "|" + photo.originalName.lowercased()
            let k = pairKey(photo)
            if let existing = pairsPerStem[s]?[k], existing <= sortKey { continue }
            pairsPerStem[s, default: [:]][k] = sortKey
        }

        // Number colliding shots chronologically.
        var counterForPair: [String: [String: Int]] = [:]   // stem → pairKey → counter
        for (s, pairs) in pairsPerStem where pairs.count > 1 {
            let ordered = pairs.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            for (i, pair) in ordered.enumerated() { counterForPair[s, default: [:]][pair.key] = i + 1 }
        }

        for photo in photos {
            let base = baseNames[photo.id] ?? photo.originalName
            let newName: String
            if let n = counterForPair[stem(base)]?[pairKey(photo)] {
                if hasCounter {
                    newName = FormatEngine.fileName(format: format, exif: photo.exifData ?? EXIFData(), counter: n)
                } else {
                    let ext = (base as NSString).pathExtension
                    let stem = (base as NSString).deletingPathExtension
                    newName = stem + FormatEngine.counterSuffix(n) + (ext.isEmpty ? "" : ".\(ext)")
                }
            } else {
                newName = base
            }
            if photo.proposedName != newName {
                photo.proposedName = newName
                photo.status = .pending   // name changed → can be renamed again
            }
        }
    }

    func renameAll() async {
        guard let style = selectedStyle, canRename else { return }
        let batch = pendingPhotos           // snapshot: the list may change while we work
        isProcessing = true
        processedCount = 0
        processingTotal = batch.count
        errorMessage = nil
        defer { isProcessing = false }

        let outcome = await RenameService.process(
            photos: batch,
            style: style,
            outputMode: outputMode,
            conflictStrategy: conflictStrategy,
            createFolders: effectiveCreateFolders,
            includeSidecars: includeSidecars,
            progress: { [weak self] done in self?.processedCount = done }
        )
        lastBatchOperations = outcome.operations
        RenameLog.write(outcome.operations, action: "rename")

        var failed = 0, skipped = 0
        for (photo, result) in zip(batch, outcome.results) {
            switch result {
            case .success:       photo.status = .renamed
            case .skipped:       photo.status = .skipped; skipped += 1
            case .failed(let e): photo.status = .failed(e.localizedDescription); failed += 1
            }
        }
        if failed > 0 {
            errorMessage = String(localized: "\(failed) of \(batch.count) file(s) could not be processed. See the Status column for details.")
        } else if skipped > 0 {
            errorMessage = String(localized: "\(skipped) of \(batch.count) file(s) were skipped.")
        }
    }

    /// Reverts the last rename batch (moves back, removes copies and created folders).
    func undoLastBatch() async {
        guard canUndo else { return }
        let operations = lastBatchOperations
        lastBatchOperations = []
        isProcessing = true
        processedCount = 0
        processingTotal = 0
        errorMessage = nil
        defer { isProcessing = false }

        let outcome = await RenameService.undo(operations)
        RenameLog.write(outcome.undone, action: "undo")

        let affected = Set(operations.compactMap(\.photoID))
        for photo in photos where affected.contains(photo.id) {
            photo.status = .pending
        }
        if outcome.failed > 0 {
            errorMessage = String(localized: "\(outcome.failed) change(s) could not be undone.")
        } else if outcome.notRestorable > 0 {
            errorMessage = String(localized: "Undone. \(outcome.notRestorable) overwritten file(s) remain in the Trash.")
        }
    }
}
