import AppKit
import SwiftUI

@main
struct TimeMachineAnalyzerApp: App {
    @StateObject private var viewModel = AppViewModel()
    @State private var showingAbout = false

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("Time Machine Analyzer") {
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
                Button("About Time Machine Analyzer") {
                    showingAbout = true
                }
            }
        }
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
