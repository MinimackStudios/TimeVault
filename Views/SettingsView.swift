import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var updateController: UpdateController
    @State private var selection: SettingsPane = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsPane(updateController: updateController)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsPane.general)

            AccessSettingsPane(viewModel: viewModel)
                .tabItem {
                    Label("Access", systemImage: "lock.shield")
                }
                .tag(SettingsPane.access)
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 720, idealWidth: 720, minHeight: 500, idealHeight: 500)
    }
}

private enum SettingsPane: Hashable {
    case general
    case access
}

private struct GeneralSettingsPane: View {
    @ObservedObject var updateController: UpdateController
    @AppStorage("showSnapshotPaths") private var showSnapshotPaths = true
    @AppStorage("showDetailedScanProgress") private var showDetailedScanProgress = true

    var body: some View {
        SettingsPaneContent(
            title: "General",
            subtitle: "Choose which details are visible while browsing and comparing snapshots.")
        {
            Toggle(isOn: $showSnapshotPaths) {
                SettingsToggleLabel(
                    title: "Show snapshot paths",
                    detail: "Display the full read-only path below each selected snapshot.",
                    systemImage: "folder"
                )
            }
            Toggle(isOn: $showDetailedScanProgress) {
                SettingsToggleLabel(
                    title: "Show detailed scan progress",
                    detail: "Show the current phase, item count, elapsed time, and scan rate while comparing.",
                    systemImage: "chart.bar.xaxis"
                )
            }

            Divider()

            UpdaterSettingsSection(updateController: updateController)
        }
    }
}

private struct UpdaterSettingsSection: View {
    @ObservedObject var updateController: UpdateController
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updateController: UpdateController) {
        self.updateController = updateController
        _automaticallyChecksForUpdates = State(
            initialValue: updateController.automaticallyChecksForUpdates
        )
        _automaticallyDownloadsUpdates = State(
            initialValue: updateController.automaticallyDownloadsUpdates
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Software Updates")
                        .font(.body.weight(.medium))
                    Text("TimeVault can check for signed updates and install them when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("Check Now") {
                    updateController.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .disabled(!updateController.canCheckForUpdates)
            }

            Toggle(
                "Automatically check for updates",
                isOn: $automaticallyChecksForUpdates
            )
            .onChange(of: automaticallyChecksForUpdates) { newValue in
                updateController.setAutomaticallyChecksForUpdates(newValue)
                if !newValue {
                    automaticallyDownloadsUpdates = false
                }
            }

            Toggle(
                "Download and install updates automatically",
                isOn: $automaticallyDownloadsUpdates
            )
            .disabled(!automaticallyChecksForUpdates)
            .onChange(of: automaticallyDownloadsUpdates) { newValue in
                updateController.setAutomaticallyDownloadsUpdates(newValue)
            }
        }
    }
}

private struct AccessSettingsPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        SettingsPaneContent(
            title: "Access",
            subtitle: "macOS controls access to Time Machine volumes and protected backup locations.")
        {
            SettingsActionRow(
                title: "Approve a backup volume",
                detail: "Choose a mounted Time Machine volume and grant this app read-only access.",
                systemImage: "externaldrive.badge.checkmark",
                actionTitle: "Choose Volume…",
                action: viewModel.chooseBackupVolume
            )
            SettingsActionRow(
                title: "Full Disk Access",
                detail: "Open macOS Privacy & Security settings if protected backup folders cannot be read.",
                systemImage: "checkmark.shield",
                actionTitle: "Open Settings…",
                action: viewModel.openFullDiskAccessSettings
            )
            SettingsActionRow(
                title: "Detected drives",
                detail: accessStatus,
                systemImage: "arrow.clockwise",
                actionTitle: "Refresh",
                action: viewModel.refreshMountedVolumes
            )

            Divider()

            SettingsInformationRow(
                title: "Time Machine formats",
                detail: "Some APFS Time Machine internals are not exposed through public APIs. The app uses readable file-system paths and tmutil output when available.",
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    private var accessStatus: String {
        if let selectedVolume = viewModel.selectedVolume {
            switch viewModel.permissionState {
            case .verified:
                return "Read access verified for \(selectedVolume.lastPathComponent)."
            case .inaccessible(let detail):
                return detail
            case .unknown:
                return "Access has not been verified for \(selectedVolume.lastPathComponent)."
            }
        }
        return "No backup volume is currently selected."
    }

}

private struct SettingsPaneContent<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                content
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 54)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsToggleLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
        }
    }
}

private struct SettingsInformationRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
    }
}
