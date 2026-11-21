import SwiftUI

struct StyleSelectorView: View {
    @Environment(AppViewModel.self) var vm
    @State private var editingStyle: NamingStyle?
    @State private var confirmDelete = false

    private static let lastStyleKey = "lastSelectedStyleID"

    var body: some View {
        HStack {
            Picker("Style:", selection: Binding(
                get: { vm.selectedStyleID },
                set: { select($0) }
            )) {
                ForEach(vm.styles) { style in
                    Text(style.name).tag(Optional(style.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            Button { editingStyle = vm.selectedStyle } label: {
                Image(systemName: vm.selectedStyle?.isBuiltIn == true ? "eye" : "pencil")
            }
            .help(vm.selectedStyle?.isBuiltIn == true ? Text("View style") : Text("Edit style"))
            .disabled(vm.selectedStyle == nil)

            Menu {
                Button("New Style…") {
                    editingStyle = NamingStyle(name: String(localized: "New Style"), formatString: "%Y%M%D_%h%m%s%C.%F")
                }
                Button("Duplicate Style…") { duplicateSelected() }
                    .disabled(vm.selectedStyle == nil)
                Divider()
                Button("Delete Style…", role: .destructive) { confirmDelete = true }
                    .disabled(vm.selectedStyle == nil || vm.selectedStyle?.isBuiltIn == true)
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.visible)
            .fixedSize()
            .help("New, duplicate or delete style")
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { restoreLastStyle() }
        // sheet(item:) guarantees the sheet always gets the style it was opened with
        .sheet(item: $editingStyle) { style in
            StyleEditorView(style: style, previewEXIF: vm.photos.first?.exifData) { updated in
                save(updated)
            }
        }
        .confirmationDialog("Delete style \"\(vm.selectedStyle?.name ?? "")\"?",
                            isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { deleteSelected() }
        }
    }

    private func select(_ id: UUID?) {
        vm.selectedStyleID = id
        vm.refreshProposedNames()
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: Self.lastStyleKey)
        }
    }

    private func save(_ updated: NamingStyle) {
        if let idx = vm.styles.firstIndex(where: { $0.id == updated.id }) {
            vm.styles[idx] = updated
        } else {
            vm.styles.append(updated)
        }
        StyleStore.shared.save(vm.styles)
        select(updated.id)
    }

    private func duplicateSelected() {
        guard let s = vm.selectedStyle else { return }
        var copy = s
        copy.id = UUID()
        copy.name = String(localized: "\(s.name) Copy")
        copy.isBuiltIn = false
        editingStyle = copy
    }

    private func deleteSelected() {
        guard let s = vm.selectedStyle, !s.isBuiltIn else { return }
        vm.styles.removeAll { $0.id == s.id }
        StyleStore.shared.save(vm.styles)
        select(vm.styles.first?.id)
    }

    private func restoreLastStyle() {
        guard let saved = UserDefaults.standard.string(forKey: Self.lastStyleKey),
              let uuid  = UUID(uuidString: saved),
              vm.styles.contains(where: { $0.id == uuid })
        else { return }
        vm.selectedStyleID = uuid
        vm.refreshProposedNames()
    }
}
