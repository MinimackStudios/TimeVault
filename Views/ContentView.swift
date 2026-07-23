import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            Group {
                switch viewModel.section {
                case .welcome: WelcomeView(viewModel: viewModel)
                case .snapshots: SnapshotSelectionView(viewModel: viewModel)
                case .comparison: ComparisonResultsView(viewModel: viewModel)
            }
            }
            .overlay(alignment: .bottom) {
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message, diagnostics: viewModel.diagnostics) { viewModel.errorMessage = nil }
                        .padding()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.section) {
            Label("Welcome", systemImage: "house")
                .font(.body.weight(.medium))
                .padding(.vertical, 3)
                .tag(AppSection.welcome)
            Section("Backup drives") {
                ForEach(viewModel.mountedVolumes, id: \.self) { volume in
                    Button {
                        viewModel.selectVolume(volume)
                        viewModel.section = .snapshots
                        viewModel.discoverSnapshots()
                    } label: {
                        Label(volume.lastPathComponent, systemImage: "externaldrive")
                            .font(.body.weight(.medium))
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !viewModel.snapshots.isEmpty {
                Label("Snapshots", systemImage: "clock.arrow.circlepath")
                    .font(.body.weight(.medium))
                    .padding(.vertical, 3)
                    .tag(AppSection.snapshots)
            }
            if viewModel.comparison != nil {
                Label("Comparison", systemImage: "arrow.left.and.right")
                    .font(.body.weight(.medium))
                    .padding(.vertical, 3)
                    .tag(AppSection.comparison)
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 38)
        .disabled(viewModel.isComparing || viewModel.isDiscovering)
        .safeAreaInset(edge: .bottom) {
            Button { viewModel.refreshMountedVolumes() } label: {
                Label("Refresh drives", systemImage: "arrow.clockwise")
            }
            .padding(8)
            .disabled(viewModel.isComparing || viewModel.isDiscovering)
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("TimeVault").font(.largeTitle.bold())
            Text("Compare two read-only backup snapshots to understand what changed, where it changed, and how much logical file data was added or removed.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .foregroundStyle(.secondary)
            HStack {
                Button("Choose a backup drive", systemImage: "externaldrive.badge.plus") { viewModel.chooseBackupVolume() }
                    .buttonStyle(.borderedProminent)
            }
            Text("The app only reads metadata and never modifies, restores, or deletes backup content.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String
    let diagnostics: String?
    let dismiss: () -> Void
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message).font(.callout)
                Spacer()
                Button("Dismiss", action: dismiss).buttonStyle(.borderless)
            }
            if let diagnostics {
                DisclosureGroup("Technical details", isExpanded: $showDiagnostics) { Text(diagnostics).font(.caption.monospaced()).textSelection(.enabled) }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.orange.opacity(0.6)))
        .shadow(radius: 6)
    }
}
