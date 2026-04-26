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
        let new = urls.filter { !existing.contains($0) }.map { Photo(url: $0) }
        for photo in new {
            photo.exifData = EXIFReader.read(url: photo.url)
        }
        photos.append(contentsOf: new)
        refreshProposedNames()
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
        for photo in photos {
            let base = FormatEngine.resolve(format: style.formatString, exif: photo.exifData ?? EXIFData(), counter: nil)
            baseNames[photo.id] = base
        }
        // Detect collisions and inject counter
        var counts: [String: Int] = [:]
        for name in baseNames.values { counts[name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        for photo in photos {
            let base = baseNames[photo.id] ?? photo.originalName
            if counts[base, default: 0] > 1 {
                seen[base, default: 0] += 1
                photo.proposedName = FormatEngine.resolve(format: style.formatString, exif: photo.exifData ?? EXIFData(), counter: seen[base])
            } else {
                photo.proposedName = base
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
        for (photo, result) in zip(photos, results) {
            switch result {
            case .success:      photo.status = .renamed
            case .skipped:      photo.status = .skipped
            case .failed(let e): photo.status = .failed(e.localizedDescription)
            }
        }
    }
}
