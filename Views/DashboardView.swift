import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TimeVault")
                            .font(.largeTitle.bold())
                        Text("Your Time Machine protection at a glance")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        viewModel.refreshSystemOverview()
                    }
                    .disabled(viewModel.isRefreshingSystemOverview)
                }

                if let overview = viewModel.systemOverview {
                    DashboardHero(
                        activity: overview.backupActivity,
                        lastBackup: overview.lastBackupPath.map(lastBackupDescription) ?? "Last backup is unavailable",
                        tint: backupTint(for: overview.backupActivity),
                        browseSnapshots: { viewModel.showSnapshotBrowser() },
                        addBackupDrive: { viewModel.chooseBackupVolume() }
                    )

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        DashboardMetricCard(
                            title: "Local snapshots",
                            value: "\(overview.localSnapshotCount)",
                            detail: "On \(overview.startupVolumeName)",
                            image: "clock.arrow.circlepath",
                            tint: .blue
                        )
                        DashboardMetricCard(
                            title: "Startup disk",
                            value: overview.availableCapacity.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unavailable",
                            detail: storageDescription(for: overview),
                            image: "internaldrive",
                            tint: .purple
                        )
                        DashboardMetricCard(
                            title: "Backup drives",
                            value: "\(viewModel.mountedVolumes.count)",
                            detail: viewModel.mountedVolumes.isEmpty ? "Connect or choose a backup drive" : "Available to TimeVault",
                            image: "externaldrive.fill",
                            tint: .orange
                        )
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                        DashboardStorageCard(overview: overview)
                        DashboardSnapshotCard(
                            count: overview.localSnapshotCount,
                            volumeName: overview.startupVolumeName,
                            browseSnapshots: { viewModel.showSnapshotBrowser() }
                        )
                    }

                    Text("Updated \(overview.refreshedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if viewModel.isRefreshingSystemOverview {
                    DashboardEmptyState(
                        title: "Loading TimeVault status",
                        detail: "Reading local, non-destructive system information.",
                        image: "clock.arrow.circlepath"
                    )
                } else {
                    DashboardEmptyState(
                        title: "Dashboard unavailable",
                        detail: "Refresh to read this Mac's current Time Machine status.",
                        image: "exclamationmark.triangle"
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: 1_260, alignment: .topLeading)
        }
    }

    private func backupTint(for activity: BackupActivity) -> Color {
        switch activity {
        case .running: .orange
        case .idle: .green
        case .unavailable: .secondary
        }
    }

    private func lastBackupDescription(_ path: String) -> String {
        guard let date = SystemStatusService.snapshotDate(in: path) else {
            return "Last backup date is unavailable"
        }
        return "Last backup: \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func storageDescription(for overview: SystemOverview) -> String {
        guard let totalCapacity = overview.totalCapacity else { return "Total capacity unavailable" }
        return "\(ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)) total capacity"
    }
}

private struct DashboardHero: View {
    let activity: BackupActivity
    let lastBackup: String
    let tint: Color
    let browseSnapshots: () -> Void
    let addBackupDrive: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: activity.systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text("TIME MACHINE STATUS")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(activity.title)
                    .font(.title2.bold())
                Text(lastBackup)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 9) {
                Button("Browse snapshots", systemImage: "clock.arrow.circlepath", action: browseSnapshots)
                    .buttonStyle(.borderedProminent)
                Button("Add backup drive", systemImage: "externaldrive.badge.plus", action: addBackupDrive)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), Color.blue.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let image: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: image)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                Spacer()
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct DashboardStorageCard: View {
    let overview: SystemOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Startup disk", systemImage: "internaldrive")
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(overview.startupVolumeName)
                    .font(.title3.weight(.semibold))
                Spacer()
                if let availableCapacity = overview.availableCapacity {
                    Text("\(ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let usedCapacity = overview.usedCapacity, let totalCapacity = overview.totalCapacity, totalCapacity > 0 {
                ProgressView(value: Double(usedCapacity), total: Double(totalCapacity))
                    .tint(.purple)
                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)) used")
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)) total")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Capacity information is unavailable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct DashboardSnapshotCard: View {
    let count: Int
    let volumeName: String
    let browseSnapshots: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Snapshot storage", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Text("\(count) local snapshots")
                .font(.title3.weight(.semibold))
            Text("Local Time Machine history stored on \(volumeName), available even when your backup drive is disconnected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Button("View local snapshots", systemImage: "arrow.right", action: browseSnapshots)
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct DashboardEmptyState: View {
    let title: String
    let detail: String
    let image: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: image)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
