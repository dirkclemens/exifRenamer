import SwiftUI

struct OutputOptionsView: View {
    @Environment(AppViewModel.self) var vm
    @State private var useCustomFolder = false
    @State private var customFolderURL: URL?

    var body: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Save to custom folder", isOn: $useCustomFolder)
                    .onChange(of: useCustomFolder) { _, new in
                        if !new { vm.outputMode = .sameFolder }
                        else if let url = customFolderURL { vm.outputMode = .customFolder(url) }
                    }

                if useCustomFolder {
                    HStack {
                        Text(customFolderURL?.path ?? "No folder selected")
                            .foregroundStyle(customFolderURL == nil ? .red : .secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }

                Toggle("Create subfolders from EXIF pattern", isOn: Binding(
                    get: { vm.createFolders },
                    set: { vm.createFolders = $0 }
                ))
                .disabled(vm.selectedStyle?.folderFormatString == nil)
                .help(vm.selectedStyle?.folderFormatString == nil ? "Set a folder pattern in the style editor first." : "")

                Divider()

                Picker("On conflict:", selection: Binding(
                    get: { vm.conflictStrategy },
                    set: { vm.conflictStrategy = $0 }
                )) {
                    ForEach(ConflictStrategy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            .padding(4)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            customFolderURL = url
            vm.outputMode = .customFolder(url)
        }
    }
}
