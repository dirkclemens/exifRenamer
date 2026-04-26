import SwiftUI

struct StyleEditorView: View {
    @State private var style: NamingStyle
    @State private var useFolderPattern: Bool
    var onSave: (NamingStyle) -> Void
    @Environment(\.dismiss) private var dismiss

    // Sample EXIF for preview
    private static var sampleEXIF: EXIFData = {
        var e = EXIFData()
        let df = DateFormatter(); df.dateFormat = "yyyy:MM:dd HH:mm:ss"
        e.dateTimeOriginal = df.date(from: "2026:04:26 14:30:00")
        e.make = "Canon"; e.model = "EOS R5"; e.lensModel = "RF 24-70mm"
        e.iso = 400; e.fileExtension = "jpg"
        return e
    }()

    init(style: NamingStyle, onSave: @escaping (NamingStyle) -> Void) {
        _style = State(initialValue: style)
        _useFolderPattern = State(initialValue: style.folderFormatString != nil)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(style.isBuiltIn ? "View Style (built-in)" : "Edit Style")
                .font(.title2).bold()

            LabeledContent("Name:") {
                TextField("Style name", text: $style.name).disabled(style.isBuiltIn)
            }

            LabeledContent("Filename format:") {
                TextField("e.g. %Y%M%D_%h%m%s%C.%F", text: $style.formatString)
                    .disabled(style.isBuiltIn)
                    .font(.monospaced(.body)())
            }

            // Token legend
            tokenLegend

            LabeledContent("Preview:") {
                Text(FormatEngine.preview(format: style.formatString, exif: Self.sampleEXIF))
                    .font(.monospaced(.body)())
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Create subfolders using pattern:", isOn: $useFolderPattern)

            if useFolderPattern {
                LabeledContent("Folder pattern:") {
                    TextField("e.g. %Y/%Y-%M-%D", text: Binding(
                        get: { style.folderFormatString ?? "" },
                        set: { style.folderFormatString = $0.isEmpty ? nil : $0 }
                    ))
                    .disabled(style.isBuiltIn)
                    .font(.monospaced(.body)())
                }
                LabeledContent("Folder preview:") {
                    Text(FormatEngine.preview(format: style.folderFormatString ?? "", exif: Self.sampleEXIF))
                        .font(.monospaced(.body)())
                        .foregroundStyle(.secondary)
                }
            } else {
                Color.clear.frame(height: 0).onChange(of: useFolderPattern) { _, new in
                    if !new { style.folderFormatString = nil }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                if !style.isBuiltIn {
                    Button("Save") { onSave(style); dismiss() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 480, height: 460)
    }

    private var tokenLegend: some View {
        GroupBox("Available tokens") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 4) {
                ForEach(FormatToken.allCases, id: \.rawValue) { token in
                    HStack(spacing: 4) {
                        Text(token.rawValue).font(.monospaced(.caption)()).bold()
                        Text(token.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
