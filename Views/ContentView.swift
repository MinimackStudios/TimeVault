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
                case .dashboard: DashboardView(viewModel: viewModel)
                case .snapshots: SnapshotSelectionView(viewModel: viewModel)
                case .comparison: ComparisonResultsView(viewModel: viewModel)
            }
            }
            .overlay(alignment: .bottom) {
                if let message = viewModel.errorMessage {
                    ErrorBanner(
                        message: message,
                        diagnostics: viewModel.diagnostics,
                        showsPermissionRecovery: viewModel.shouldShowPermissionRecovery,
                        checkPermission: viewModel.recheckSelectedVolumeAccess,
                        openFullDiskAccessSettings: viewModel.openFullDiskAccessSettings,
                        chooseBackupVolume: viewModel.chooseBackupVolume
                    ) { viewModel.errorMessage = nil }
                        .padding()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var expandedVolumePaths: Set<String> = []

    var body: some View {
        List(selection: Binding(
            get: { viewModel.section },
            set: { destination in
                guard destination != viewModel.section else { return }
                DispatchQueue.main.async { viewModel.navigate(to: destination) }
            }
        )) {
            Label("Dashboard", systemImage: "rectangle.3.group")
                .font(.body.weight(.medium))
                .padding(.vertical, 3)
                .tag(AppSection.dashboard)
            Section("Backup drives") {
                ForEach(viewModel.mountedVolumes, id: \.self) { volume in
                    DisclosureGroup(isExpanded: expansionBinding(for: volume)) {
                        Label("Snapshot Browser", systemImage: "clock.arrow.circlepath")
                            .font(.body.weight(.medium))
                            .padding(.vertical, 3)
                            .tag(AppSection.snapshots(volume))
                    } label: {
                        Label(volume.lastPathComponent, systemImage: "externaldrive")
                            .font(.body.weight(.medium))
                            .padding(.vertical, 3)
                    }
                }
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
        .onAppear {
            expandedVolumePaths.formUnion(viewModel.mountedVolumes.map(\.path))
        }
        .onReceive(viewModel.$mountedVolumes) { volumes in
            expandedVolumePaths.formUnion(volumes.map(\.path))
        }
        .safeAreaInset(edge: .bottom) {
            Button { viewModel.refreshMountedVolumes() } label: {
                Label("Refresh drives", systemImage: "arrow.clockwise")
            }
            .padding(8)
            .disabled(viewModel.isComparing || viewModel.isDiscovering)
        }
    }

    private func expansionBinding(for volume: URL) -> Binding<Bool> {
        Binding(
            get: { expandedVolumePaths.contains(volume.path) },
            set: { isExpanded in
                if isExpanded {
                    expandedVolumePaths.insert(volume.path)
                } else {
                    expandedVolumePaths.remove(volume.path)
                }
            }
        )
    }
}

struct ErrorBanner: View {
    let message: String
    let diagnostics: String?
    let showsPermissionRecovery: Bool
    let checkPermission: () -> Void
    let openFullDiskAccessSettings: () -> Void
    let chooseBackupVolume: () -> Void
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
            if showsPermissionRecovery {
                HStack(spacing: 12) {
                    Button("Check Again", action: checkPermission)
                    Button("Open Full Disk Access", action: openFullDiskAccessSettings)
                    Button("Choose Volume Again", action: chooseBackupVolume)
                }
                .buttonStyle(.bordered)
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
