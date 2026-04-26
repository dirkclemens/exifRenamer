//
//  exifRenamerApp.swift
//  exifRenamer
//

import SwiftUI

@main
struct exifRenamerApp: App {
    @State private var vm = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(vm)
        }
        Settings {
            SettingsView()
        }
    }
}
