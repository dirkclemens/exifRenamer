import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) var vm
    @AppStorage(ConflictStrategy.defaultsKey) private var conflictRaw: String = ConflictStrategy.autoNumber.rawValue
    @AppStorage(RenameLog.enabledKey) private var writeLog = true
    @State private var grantedFolders: [String] = FolderAccessManager.shared.grantedFolders

    var body: some View {
        Form {
            Picker("Default conflict strategy:", selection: $conflictRaw) {
                ForEach(ConflictStrategy.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .onChange(of: conflictRaw) { _, new in
                if let s = ConflictStrategy(rawValue: new) { vm.conflictStrategy = s }
            }

            LabeledContent("Rename log:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Write a log file for every rename", isOn: $writeLog)
                    Button("Show Logs in Finder") { RenameLog.revealInFinder() }
                }
            }

            LabeledContent("Folder permissions:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(grantedFolders.count) folder(s) remembered")
                        .foregroundStyle(.secondary)
                        .help(grantedFolders.joined(separator: "\n"))
                    Button("Reset Folder Permissions") {
                        FolderAccessManager.shared.forgetAll()
                        grantedFolders = []
                    }
                    .disabled(grantedFolders.isEmpty)
                }
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { grantedFolders = FolderAccessManager.shared.grantedFolders }
    }
}
