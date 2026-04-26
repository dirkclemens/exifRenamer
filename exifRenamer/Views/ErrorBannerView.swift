import SwiftUI

struct ErrorBannerView: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).foregroundStyle(.primary)
            Spacer()
            Button { onDismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.15))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.4)))
    }
}
