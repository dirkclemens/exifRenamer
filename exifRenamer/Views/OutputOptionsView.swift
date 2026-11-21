import SwiftUI

struct OutputOptionsView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        @Bindable var vm = vm
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Save copies to custom folder", isOn: $vm.useCustomFolder)

                if vm.useCustomFolder {
                    HStack {
                        Text(vm.customFolderURL?.path ?? "No folder selected")
                            .foregroundStyle(vm.customFolderURL == nil ? .red : .secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }

                Toggle("Create subfolders from EXIF pattern", isOn: $vm.createFolders)
                    .disabled(!hasFolderPattern)
                    .help(hasFolderPattern
                          ? "Files are copied into subfolders; originals stay in place."
                          : "Set a folder pattern in the style editor first.")

                Toggle("Include sidecar files (.xmp, .aae)", isOn: $vm.includeSidecars)
                    .help("Sidecar files with the same name are renamed or copied together with the photo.")

                Divider()

                Picker("On conflict:", selection: $vm.conflictStrategy) {
                    ForEach(ConflictStrategy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .help("Overwritten files are moved to the Trash. Files of the current batch are never overwritten.")
            }
            .padding(4)
        }
    }

    private var hasFolderPattern: Bool {
        !(vm.selectedStyle?.folderFormatString ?? "").isEmpty
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            vm.customFolderURL = url
        }
    }
}
