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
    /// format has no %C). Counters follow capture time, then original file name.
    func refreshProposedNames() {
        guard let style = selectedStyle else { return }
        let format = style.formatString
        let hasCounter = FormatEngine.containsCounter(format)

        // First pass — base names without counter
        var baseNames: [UUID: String] = [:]
        for photo in photos {
            baseNames[photo.id] = FormatEngine.fileName(format: format, exif: photo.exifData ?? EXIFData(), counter: nil)
        }

        // Detect collisions (case-insensitive, like APFS/HFS+ default volumes)
        var counts: [String: Int] = [:]
        for name in baseNames.values { counts[name.lowercased(), default: 0] += 1 }

        let ordered = photos.sorted {
            let a = $0.exifData?.sortKey ?? "", b = $1.exifData?.sortKey ?? ""
            return a != b ? a < b : $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending
        }
        var seen: [String: Int] = [:]
        for photo in ordered {
            let base = baseNames[photo.id] ?? photo.originalName
            let newName: String
            if counts[base.lowercased(), default: 0] > 1 {
                seen[base.lowercased(), default: 0] += 1
                let n = seen[base.lowercased()]!
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

        let results = await RenameService.process(
            photos: batch,
            style: style,
            outputMode: outputMode,
            conflictStrategy: conflictStrategy,
            createFolders: effectiveCreateFolders,
            progress: { [weak self] done in self?.processedCount = done }
        )

        var failed = 0, skipped = 0
        for (photo, result) in zip(batch, results) {
            switch result {
            case .success:       photo.status = .renamed
            case .skipped:       photo.status = .skipped; skipped += 1
            case .failed(let e): photo.status = .failed(e.localizedDescription); failed += 1
            }
        }
        if failed > 0 {
            errorMessage = "\(failed) of \(batch.count) file(s) could not be processed. See the Status column for details."
        } else if skipped > 0 {
            errorMessage = "\(skipped) of \(batch.count) file(s) were skipped."
        }
    }
}
