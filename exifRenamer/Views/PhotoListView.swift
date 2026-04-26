import SwiftUI

struct PhotoListView: View {
    @Environment(AppViewModel.self) var vm
    @State private var selection: Set<UUID> = []

    var body: some View {
        Table(vm.photos, selection: $selection) {
            TableColumn("Original Name", value: \.originalName)
                .width(min: 100, ideal: 160, max: .infinity)
            TableColumn("New Name", value: \.proposedName)
                .width(min: 100, ideal: 160, max: .infinity)
            TableColumn("Status") { photo in
                statusView(photo.status)
            }
            .width(min: 120, ideal: 140)
        }
        .contextMenu(forSelectionType: UUID.self, menu: { ids in
            Button("Remove", role: .destructive) {
                ids.forEach { id in
                    if let p = vm.photos.first(where: { $0.id == id }) { vm.removePhoto(p) }
                }
            }
        })
    }

    @ViewBuilder
    private func statusView(_ status: PhotoStatus) -> some View {
        switch status {
        case .pending:         Label("Pending",  systemImage: "clock").foregroundStyle(.secondary)
        case .renamed:         Label("Done",     systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:         Label("Skipped",  systemImage: "forward.fill").foregroundStyle(.orange)
        case .conflict:        Label("Conflict", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .failed(let msg): Label(msg,        systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
