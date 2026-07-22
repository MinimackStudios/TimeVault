import SwiftUI

struct SnapshotSelectionView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Choose snapshots").font(.largeTitle.bold())
                    Text(viewModel.selectedVolume?.path ?? "Folder-based comparison mode")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Choose backup drive", systemImage: "externaldrive.badge.plus") { viewModel.chooseBackupVolume() }
                    .disabled(viewModel.isComparing || viewModel.isDiscovering)
            }

            if case .inaccessible(let detail) = viewModel.permissionState {
                Label(detail, systemImage: "lock.fill").foregroundStyle(.orange).padding(.vertical, 4)
            }

            HStack(alignment: .top, spacing: 16) {
                SnapshotPicker(title: "Older snapshot", snapshot: $viewModel.olderSnapshot, snapshots: viewModel.snapshots)
                    .disabled(viewModel.isComparing || viewModel.isDiscovering)
                SnapshotPicker(title: "Newer snapshot", snapshot: $viewModel.newerSnapshot, snapshots: viewModel.snapshots)
                    .disabled(viewModel.isComparing || viewModel.isDiscovering)
            }

            if viewModel.isDiscovering {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finding available snapshots…")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }

            if viewModel.isComparing {
                ScanProgressPanel(progress: viewModel.progress) {
                    viewModel.cancelComparison()
                }
            }

            HStack {
                Button("Choose older folder", systemImage: "folder") { viewModel.chooseFolderSnapshot(isOlder: true) }
                    .disabled(viewModel.isComparing || viewModel.isDiscovering)
                Button("Choose newer folder", systemImage: "folder") { viewModel.chooseFolderSnapshot(isOlder: false) }
                    .disabled(viewModel.isComparing || viewModel.isDiscovering)
                Spacer()
                if !viewModel.isComparing {
                    Button("Compare", systemImage: "arrow.left.and.right") { viewModel.compareSnapshots() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.olderSnapshot == nil || viewModel.newerSnapshot == nil)
                }
            }

            if !viewModel.snapshots.isEmpty {
                Text("Available snapshots").font(.headline)
                List(viewModel.snapshots) { snapshot in
                    HStack {
                        Image(systemName: "clock")
                        VStack(alignment: .leading) {
                            Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                            Text([snapshot.machineName, snapshot.identifier].compactMap { $0 }.joined(separator: " • "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Use older") { viewModel.olderSnapshot = snapshot }
                            .disabled(viewModel.isComparing || viewModel.isDiscovering)
                        Button("Use newer") { viewModel.newerSnapshot = snapshot }
                            .disabled(viewModel.isComparing || viewModel.isDiscovering)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            } else if !viewModel.isDiscovering {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView("No snapshots loaded", systemImage: "clock.badge.questionmark", description: Text("Choose a Time Machine volume or choose two folders that represent snapshots."))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No snapshots loaded")
                            .font(.headline)
                        Text("Choose a Time Machine volume or choose two folders that represent snapshots.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
        }
        .padding()
    }
}

private struct ScanProgressPanel: View {
    let progress: ScanProgress?
    let cancel: () -> Void
    @AppStorage("showDetailedScanProgress") private var showDetailedScanProgress = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(alignment: .top, spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(progress?.phase ?? "Preparing comparison")
                            .font(.headline)
                        if let progress {
                            Text("• \(progress.rootName)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button("Cancel", role: .cancel, action: cancel)
                    }

                    if showDetailedScanProgress, let progress {
                        HStack(spacing: 16) {
                            ProgressMetric(title: progress.phase == "Comparing changes" ? "Paths compared" : "Items scanned", value: progress.itemsScanned.formatted())
                            ProgressMetric(title: "Rate", value: "\(progress.itemsPerSecond.formatted(.number.precision(.fractionLength(0))))/s")
                            ProgressMetric(title: "Elapsed", value: "\(elapsedTime(for: progress, at: context.date).formatted(.number.precision(.fractionLength(1))))s")
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Snapshot comparison progress")
        }
    }

    private func elapsedTime(for progress: ScanProgress, at date: Date) -> TimeInterval {
        guard let startedAt = progress.startedAt else { return progress.elapsedTime }
        return max(progress.elapsedTime, date.timeIntervalSince(startedAt))
    }
}

private struct ProgressMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

struct SnapshotPicker: View {
    let title: String
    @Binding var snapshot: BackupSnapshot?
    let snapshots: [BackupSnapshot]
    @AppStorage("showSnapshotPaths") private var showSnapshotPaths = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Picker(title, selection: $snapshot) {
                Text("Not selected").tag(nil as BackupSnapshot?)
                ForEach(snapshots) { item in
                    Text(item.date.formatted(date: .abbreviated, time: .shortened)).tag(item as BackupSnapshot?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(title)
            if showSnapshotPaths {
                Text(snapshot?.url.path ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(height: 12, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .opacity(snapshot == nil ? 0 : 1)
                    .accessibilityHidden(snapshot == nil)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
