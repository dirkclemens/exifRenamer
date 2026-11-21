import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Environment(AppViewModel.self) var vm
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [8]))
                .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                .cornerRadius(12)
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Drop photos or folders here")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button("Choose files…") { openPanel() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(AdaptiveHeight(isExpanded: vm.photos.isEmpty))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.photos.isEmpty)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        DebugLog.info("Drop started: providers=\(providers.count)")

        // loadItem calls back on arbitrary background queues — collect thread-safely.
        let collector = URLCollector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }

                if let error {
                    DebugLog.error("Drop loadItem error: \(error.localizedDescription)")
                    return
                }
                if let u = item as? URL {
                    collector.append(u)
                } else if let data = item as? Data, let parsed = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(parsed)
                } else {
                    DebugLog.error("Drop item unsupported payload type")
                }
            }
        }

        group.notify(queue: .main) {
            let urls = collector.urls
            let images = Self.imageFiles(in: urls)
            DebugLog.info("Drop complete: urls=\(urls.count), images=\(images.count)")
            vm.addPhotos(urls: images)
        }

        return true
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        if panel.runModal() == .OK {
            DebugLog.info("OpenPanel selected: \(panel.urls.count) items")
            vm.addPhotos(urls: Self.imageFiles(in: panel.urls))
        }
    }

    /// Expands folders (recursively, skipping hidden files and packages) and keeps image files.
    /// A dropped/chosen folder also grants folder-level write access, which is registered so
    /// renaming in place doesn't need an extra permission dialog.
    static func imageFiles(in urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                FolderAccessManager.shared.registerGranted(directory: url)
                let keys: [URLResourceKey] = [.isRegularFileKey]
                guard let e = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let file as URL in e where isImage(file) {
                    result.append(file)
                }
            } else if isImage(url) {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Uses the system type database, so every RAW format macOS knows (ORF, PEF, SRW, …),
    /// HEIF, WebP, AVIF etc. is accepted — not just a hard-coded extension list.
    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

/// Thread-safe URL accumulator for NSItemProvider callbacks.
nonisolated private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

private struct AdaptiveHeight: ViewModifier {
    let isExpanded: Bool
    func body(content: Content) -> some View {
        if isExpanded {
            content.frame(maxHeight: .infinity, alignment: .center)
        } else {
            content.frame(height: 120)
        }
    }
}
