import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) var vm
    @AppStorage(ConflictStrategy.defaultsKey) private var conflictRaw: String = ConflictStrategy.autoNumber.rawValue

    var body: some View {
        Form {
            Picker("Default conflict strategy:", selection: $conflictRaw) {
                ForEach(ConflictStrategy.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .onChange(of: conflictRaw) { _, new in
                if let s = ConflictStrategy(rawValue: new) { vm.conflictStrategy = s }
            }
        }
        .padding()
        .frame(width: 360)
    }
}
