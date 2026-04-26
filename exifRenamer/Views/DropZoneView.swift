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
                Text("Drop photos here")
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

        var urls: [URL] = []
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
                    DebugLog.info("Drop item URL: \(u.path)")
                    urls.append(u)
                    return
                }

                if let data = item as? Data, let parsed = URL(dataRepresentation: data, relativeTo: nil) {
                    DebugLog.info("Drop item Data->URL: \(parsed.path)")
                    urls.append(parsed)
                    return
                }

                DebugLog.error("Drop item unsupported payload type")
            }
        }

        group.notify(queue: .main) {
            let imageExts = Set(["jpg","jpeg","png","tiff","tif","heic","raw","cr2","cr3","nef","arw","dng","raf","rw2"])
            let filtered = urls.filter { imageExts.contains($0.pathExtension.lowercased()) }
            DebugLog.info("Drop complete: urls=\(urls.count), filteredImages=\(filtered.count)")
            filtered.forEach { DebugLog.info("Drop accepted: \($0.path)") }
            vm.addPhotos(urls: filtered)
        }

        return true
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            DebugLog.info("OpenPanel selected: \(panel.urls.count) files")
            panel.urls.forEach { DebugLog.info("OpenPanel file: \($0.path)") }
            vm.addPhotos(urls: panel.urls)
        }
    }
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
