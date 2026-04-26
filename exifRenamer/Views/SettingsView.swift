import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultConflictStrategy") private var conflictRaw: String = ConflictStrategy.autoNumber.rawValue

    var body: some View {
        Form {
            Picker("Default conflict strategy:", selection: $conflictRaw) {
                ForEach(ConflictStrategy.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
        }
        .padding()
        .frame(width: 360)
    }
}
