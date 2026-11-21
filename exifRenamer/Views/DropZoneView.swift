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
                if vm.isLoading {
                    ProgressView(value: Double(vm.loadedCount), total: Double(max(vm.loadingTotal, 1))) {
                        Text("Reading metadata… \(vm.loadedCount)/\(vm.loadingTotal)")
                    }
                    .frame(maxWidth: 260)
                } else {
                    Text("Drop photos or folders here")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
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
        let vm = vm
        Self.loadFileURLs(from: providers) { urls in
            Task { @MainActor in await vm.addItems(urls: urls) }
        }
        return true
    }

    /// NSItemProvider calls back on arbitrary background queues. Being `nonisolated`, the
    /// callbacks here are not main-actor-isolated, so Swift 6's runtime isolation checks
    /// can't trap; URLs are collected thread-safely and delivered once all are loaded.
    nonisolated static func loadFileURLs(from providers: [NSItemProvider],
                                                 completion: @escaping @Sendable ([URL]) -> Void) {
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

        group.notify(queue: .global(qos: .userInitiated)) {
            let urls = collector.urls
            DebugLog.info("Drop complete: urls=\(urls.count)")
            completion(urls)
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        if panel.runModal() == .OK {
            DebugLog.info("OpenPanel selected: \(panel.urls.count) items")
            let urls = panel.urls
            Task { await vm.addItems(urls: urls) }
        }
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
