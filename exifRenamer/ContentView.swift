//
//  ContentView.swift
//  exifRenamer
//

import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) var vm

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar area
            HStack(spacing: 12) {
                StyleSelectorView()
                Spacer()
                if !vm.photos.isEmpty {
                    Button("Clear", role: .destructive) { vm.clearAll() }
                    Button {
                        Task { await vm.renameAll() }
                    } label: {
                        Label(vm.isProcessing ? "Renaming…" : "Rename", systemImage: "pencil.and.list.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isProcessing || vm.selectedStyle == nil)
                }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            // Error banner
            if let msg = vm.errorMessage {
                ErrorBannerView(message: msg) { vm.errorMessage = nil }
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Drop zone (collapses when photos present)
            DropZoneView()
                .padding(.horizontal)
                .padding(.top, 8)

            // Photo table
            if !vm.photos.isEmpty {
                PhotoListView()
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            Divider().padding(.top, 8)

            // Output options
            OutputOptionsView()
                .padding([.horizontal, .bottom])
                .padding(.top, 8)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}
