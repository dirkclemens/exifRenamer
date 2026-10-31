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
}

@Observable
class AppViewModel {
    // Keeping the array named 'photos' to avoid breaking UI views,
    // but it now handles both Photo and Video items seamlessly!
    var photos: [Photo] = []
    var styles: [NamingStyle] = []
    var selectedStyleID: UUID?
    var outputMode: OutputMode = .sameFolder
    var conflictStrategy: ConflictStrategy = .autoNumber
    var createFolders: Bool = false
    var isProcessing: Bool = false
    var errorMessage: String?

    var selectedStyle: NamingStyle? {
        styles.first { $0.id == selectedStyleID }
    }

    init() {
        styles = StyleStore.shared.load()
        selectedStyleID = styles.first?.id
    }

    func addPhotos(urls: [URL]) {
        let existing = Set(photos.map { $0.url })
        // Wrap new items (both photos and videos)
        let newMedia = urls.filter { !existing.contains($0) }.map { Photo(url: $0) }
        
        // Wrap the async EXIF reading in a Task
        Task {
            for item in newMedia {
                item.exifData = await EXIFReader.read(url: item.url)
            }
            
            // Update the UI back on the Main thread
            await MainActor.run {
                self.photos.append(contentsOf: newMedia)
                self.refreshProposedNames()
            }
        }
    }

    func removePhoto(_ photo: Photo) {
        photos.removeAll { $0.id == photo.id }
    }

    func clearAll() {
        photos.removeAll()
    }

    func refreshProposedNames() {
        guard let style = selectedStyle else { return }
        // First pass — build base names without counter
        var baseNames: [UUID: String] = [:]
        for item in photos {
            let origName = item.url.deletingPathExtension().lastPathComponent
            let base = FormatEngine.resolve(format: style.formatString, exif: item.exifData ?? EXIFData(), originalName: origName, counter: nil)
            baseNames[item.id] = base
        }
        
        // Detect collisions and inject counter
        var counts: [String: Int] = [:]
        for name in baseNames.values { counts[name, default: 0] += 1 }
        
        var seen: [String: Int] = [:]
        for item in photos {
            let base = baseNames[item.id] ?? item.originalName
            if counts[base, default: 0] > 1 {
                seen[base, default: 0] += 1
                let origName = item.url.deletingPathExtension().lastPathComponent
                item.proposedName = FormatEngine.resolve(format: style.formatString, exif: item.exifData ?? EXIFData(), originalName: origName, counter: seen[base])
            } else {
                item.proposedName = base
            }
        }
    }

    @MainActor
    func renameAll() async {
        guard let style = selectedStyle else { return }
        isProcessing = true
        defer { isProcessing = false }

        let results = await RenameService.process(
            photos: photos,
            style: style,
            outputMode: outputMode,
            conflictStrategy: conflictStrategy,
            createFolders: createFolders
        )
        
        for (item, result) in zip(photos, results) {
            switch result {
            case .success:       item.status = .renamed
            case .skipped:       item.status = .skipped
            case .failed(let e): item.status = .failed(e.localizedDescription)
            }
        }
    }
}
