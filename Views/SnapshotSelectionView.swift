import SwiftUI

struct SnapshotSelectionView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var localSnapshotsExpanded = false
    @State private var showsAllLocalSnapshots = false
    @State private var snapshotSortOrder: SnapshotSortOrder = .newestFirst

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Snapshot browser").font(.largeTitle.bold())
                        Text(viewModel.selectedVolume?.path ?? "Folder-based comparison mode")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Choose backup drive", systemImage: "externaldrive.badge.plus") { viewModel.chooseBackupVolume() }
                        .disabled(viewModel.isComparing || viewModel.isDiscovering)
                }

                HStack {
                    Label("Snapshot order", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Snapshot order", selection: $snapshotSortOrder) {
                        ForEach(SnapshotSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Snapshot order")
                }

                if case .inaccessible(let detail) = viewModel.permissionState {
                    Label(detail, systemImage: "lock.fill").foregroundStyle(.orange).padding(.vertical, 4)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            localSnapshotsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(localSnapshotsExpanded ? 90 : 0))
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.tint)
                            Text("Local snapshots")
                                .font(.headline)
                            Text(viewModel.localSnapshots.count.formatted())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                            Spacer()
                            Text(localSnapshotsExpanded ? "Collapse" : "Expand")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localSnapshotsExpanded ? "Collapse local snapshots" : "Expand local snapshots")

                    if localSnapshotsExpanded {
                        Group {
                            if viewModel.localSnapshots.isEmpty {
                                Text("No local Time Machine snapshots are currently available on this Mac.")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("\(viewModel.localSnapshots.count) snapshots on \(viewModel.localSnapshots.first?.volumeName ?? "the startup disk")")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Browse in Time Machine", systemImage: "clock.arrow.circlepath") {
                                            viewModel.browseLocalSnapshots()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    ForEach(displayedLocalSnapshots) { snapshot in
                                        HStack {
                                            Image(systemName: "clock")
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(snapshot.date?.formatted(date: .abbreviated, time: .shortened) ?? snapshot.name)
                                                Text(snapshot.name)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                    }
                                    if viewModel.localSnapshots.count > 5 {
                                        HStack {
                                            Text(showsAllLocalSnapshots ? "Showing all \(viewModel.localSnapshots.count) snapshots" : "Showing the 5 \(snapshotSortOrder.shortTitle) snapshots")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button(showsAllLocalSnapshots ? "Show first 5" : "Show all") {
                                                showsAllLocalSnapshots.toggle()
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .clipped()

                GroupBox("Compare backup snapshots") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Select two accessible backup snapshots to inspect exactly what changed between them.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 16) {
                            SnapshotPicker(title: "Older snapshot", snapshot: $viewModel.olderSnapshot, snapshots: sortedBackupSnapshots)
                                .disabled(viewModel.isComparing || viewModel.isDiscovering)
                            SnapshotPicker(title: "Newer snapshot", snapshot: $viewModel.newerSnapshot, snapshots: sortedBackupSnapshots)
                                .disabled(viewModel.isComparing || viewModel.isDiscovering)
                        }
                    }
                    .padding(4)
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
                    GroupBox("Backup snapshots") {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedBackupSnapshots) { snapshot in
                                HStack {
                                    Image(systemName: "clock")
                                    VStack(alignment: .leading) {
                                        Text(snapshot.date.formatted(date: .abbreviated, time: .shortened))
                                        Text([snapshot.machineName, snapshot.identifier].compactMap { $0 }.joined(separator: " • "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Open in Finder", systemImage: "folder") {
                                        viewModel.revealSnapshotInFinder(snapshot)
                                    }
                                    .labelStyle(.iconOnly)
                                    .help("Open this backup snapshot in Finder")
                                    Button("Use older") { viewModel.olderSnapshot = snapshot }
                                        .disabled(viewModel.isComparing || viewModel.isDiscovering)
                                    Button("Use newer") { viewModel.newerSnapshot = snapshot }
                                        .disabled(viewModel.isComparing || viewModel.isDiscovering)
                                }
                                .padding(.vertical, 8)
                                if snapshot.id != sortedBackupSnapshots.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(4)
                    }
                } else if !viewModel.isDiscovering {
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
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var sortedBackupSnapshots: [BackupSnapshot] {
        viewModel.snapshots.sorted { left, right in
            switch snapshotSortOrder {
            case .oldestFirst:
                return left.date < right.date
            case .newestFirst:
                return left.date > right.date
            }
        }
    }

    private var sortedLocalSnapshots: [LocalSnapshot] {
        viewModel.localSnapshots.sorted { left, right in
            switch snapshotSortOrder {
            case .oldestFirst:
                return (left.date ?? .distantPast) < (right.date ?? .distantPast)
            case .newestFirst:
                return (left.date ?? .distantPast) > (right.date ?? .distantPast)
            }
        }
    }

    private var displayedLocalSnapshots: ArraySlice<LocalSnapshot> {
        showsAllLocalSnapshots ? sortedLocalSnapshots[...] : sortedLocalSnapshots.prefix(5)
    }
}

private enum SnapshotSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: "Newest first"
        case .oldestFirst: "Oldest first"
        }
    }

    var shortTitle: String {
        switch self {
        case .newestFirst: "newest"
        case .oldestFirst: "oldest"
        }
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

                    scanProgressBar

                    if let progress {
                        Text(progressDescription(for: progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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

    @ViewBuilder
    private var scanProgressBar: some View {
        if let progress, let estimatedItemCount = progress.estimatedItemCount, estimatedItemCount > 0 {
            ProgressView(
                value: min(Double(progress.itemsScanned), Double(estimatedItemCount)),
                total: Double(estimatedItemCount)
            )
            .progressViewStyle(.linear)
            .tint(.accentColor)
            .accessibilityLabel("Comparison progress")
            .accessibilityValue("\(progress.itemsScanned) of \(estimatedItemCount) items")
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .accessibilityLabel("Comparison scan in progress")
        }
    }

    private func progressDescription(for progress: ScanProgress) -> String {
        guard let estimatedItemCount = progress.estimatedItemCount, estimatedItemCount > 0 else {
            return "\(progress.itemsScanned.formatted()) items scanned"
        }

        let completed = min(progress.itemsScanned, estimatedItemCount)
        let percentage = (Double(completed) / Double(estimatedItemCount)).formatted(.percent.precision(.fractionLength(0)))
        let itemLabel = progress.phase == "Comparing changes" ? "paths compared" : "items scanned"
        return "\(completed.formatted()) of \(estimatedItemCount.formatted()) \(itemLabel) (\(percentage))"
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
