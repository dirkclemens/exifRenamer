import SwiftUI

struct StyleEditorView: View {
    @State private var style: NamingStyle
    @State private var useFolderPattern: Bool
    private let previewEXIF: EXIFData
    var onSave: (NamingStyle) -> Void
    @Environment(\.dismiss) private var dismiss

    // Synthetic EXIF for preview when no photo is loaded
    private static let sampleEXIF: EXIFData = {
        var e = EXIFData()
        e.captureDate = DateComponents(year: 2026, month: 4, day: 26, hour: 14, minute: 30, second: 0)
        e.make = "Canon"; e.model = "EOS R5"; e.lensModel = "RF 24-70mm"
        e.iso = 400; e.fileExtension = "jpg"
        return e
    }()

    /// - Parameter previewEXIF: EXIF of a real photo (e.g. the first dropped one); falls back to a sample.
    init(style: NamingStyle, previewEXIF: EXIFData? = nil, onSave: @escaping (NamingStyle) -> Void) {
        _style = State(initialValue: style)
        _useFolderPattern = State(initialValue: style.folderFormatString != nil)
        self.previewEXIF = previewEXIF ?? Self.sampleEXIF
        self.onSave = onSave
    }

    private var trimmedName: String { style.name.trimmingCharacters(in: .whitespaces) }

    private var validationMessage: String? {
        if trimmedName.isEmpty { return String(localized: "Please enter a name.") }
        if style.formatString.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Please enter a filename format.") }
        if FormatEngine.preview(format: style.formatString, exif: previewEXIF).isEmpty { return String(localized: "The format produces an empty filename.") }
        if !style.formatString.contains(FormatToken.ext.rawValue) { return String(localized: "Tip: add \(".%F") to keep the file extension.") }
        return nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && !FormatEngine.preview(format: style.formatString, exif: previewEXIF).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(style.isBuiltIn ? LocalizedStringKey("View Style (built-in)") : LocalizedStringKey("Edit Style"))
                .font(.title2).bold()

            LabeledContent("Name:") {
                TextField("Style name", text: $style.name).disabled(style.isBuiltIn)
            }

            LabeledContent("Filename format:") {
                TextField("e.g. \("%Y%M%D_%h%m%s%C.%F")", text: $style.formatString)
                    .disabled(style.isBuiltIn)
                    .font(.monospaced(.body)())
            }

            // Token legend
            tokenLegend

            LabeledContent("Preview:") {
                Text(FormatEngine.preview(format: style.formatString, exif: previewEXIF))
                    .font(.monospaced(.body)())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            Toggle("Create subfolders using pattern:", isOn: $useFolderPattern)
                .disabled(style.isBuiltIn)
                .onChange(of: useFolderPattern) { _, new in
                    if !new { style.folderFormatString = nil }
                }

            if useFolderPattern {
                LabeledContent("Folder pattern:") {
                    TextField("e.g. \("%Y/%Y-%M-%D")", text: Binding(
                        get: { style.folderFormatString ?? "" },
                        set: { style.folderFormatString = $0.isEmpty ? nil : $0 }
                    ))
                    .disabled(style.isBuiltIn)
                    .font(.monospaced(.body)())
                }
                LabeledContent("Folder preview:") {
                    Text(FormatEngine.folderPreview(format: style.folderFormatString ?? "", exif: previewEXIF))
                        .font(.monospaced(.body)())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                if !style.isBuiltIn, let msg = validationMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(style.isBuiltIn ? LocalizedStringKey("Close") : LocalizedStringKey("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !style.isBuiltIn {
                    Button("Save") {
                        style.name = trimmedName
                        onSave(style)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
            }
        }
        .padding()
        .frame(width: 480, height: 480)
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
