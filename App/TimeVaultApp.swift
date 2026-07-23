import AppKit
import SwiftUI

@main
struct TimeVaultApp: App {
    @StateObject private var viewModel = AppViewModel()
    @State private var showingAbout = false

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("TimeVault") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 980, minHeight: 640)
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
                .tint(Color(nsColor: .controlAccentColor))
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1_880, height: 1_080)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About TimeVault") {
                    showingAbout = true
                }
            }
        }
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
