import SwiftUI

struct StyleSelectorView: View {
    @Environment(AppViewModel.self) var vm
    @State private var showEditor = false
    @State private var editingStyle: NamingStyle?

    private static let lastStyleKey = "lastSelectedStyleID"

    var body: some View {
        HStack {
            Picker("Style:", selection: Binding(
                get: { vm.selectedStyleID },
                set: {
                    vm.selectedStyleID = $0
                    vm.refreshProposedNames()
                    if let id = $0 {
                        UserDefaults.standard.set(id.uuidString, forKey: Self.lastStyleKey)
                    }
                }
            )) {
                ForEach(vm.styles) { style in
                    Text(style.name).tag(Optional(style.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            Button { editingStyle = vm.selectedStyle ?? NamingStyle(name: "", formatString: ""); showEditor = true } label: {
                Image(systemName: "pencil")
            }
            .help("Edit style")

            Button { editingStyle = NamingStyle(name: "New Style", formatString: "%Y%M%D_%h%m%s%C.%F"); showEditor = true } label: {
                Image(systemName: "plus")
            }
            .help("New style")
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { restoreLastStyle() }
        .sheet(isPresented: $showEditor) {
            if let s = editingStyle {
                StyleEditorView(style: s) { updated in
                    if let idx = vm.styles.firstIndex(where: { $0.id == updated.id }) {
                        vm.styles[idx] = updated
                    } else {
                        vm.styles.append(updated)
                        vm.selectedStyleID = updated.id
                    }
                    StyleStore.shared.save(vm.styles)
                    vm.refreshProposedNames()
                    if let id = vm.selectedStyleID {
                        UserDefaults.standard.set(id.uuidString, forKey: Self.lastStyleKey)
                    }
                }
            }
        }
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
