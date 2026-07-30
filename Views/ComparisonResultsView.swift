import Charts
import SwiftUI

struct ComparisonResultsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedView: ComparisonResultsSection = .changes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let comparison = viewModel.comparison {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Comparison results").font(.largeTitle.bold())
                        Text("\(comparison.olderSnapshot.date.formatted()) to \(comparison.newerSnapshot.date.formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        Button("Export JSON") { viewModel.exportJSON() }
                        Button("Export CSV") { viewModel.exportCSV() }
                    }
                }
                SummaryHeader(summary: comparison.summary)
                if !comparison.warnings.isEmpty {
                    ComparisonWarningsView(warnings: comparison.warnings)
                }
                Picker("Results view", selection: $selectedView) {
                    ForEach(ComparisonResultsSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                .accessibilityLabel("Results view")

                switch selectedView {
                case .changes:
                    ChartSummary(summary: comparison.summary)
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            TextField("Search paths", text: $viewModel.searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)
                            Picker("Filter", selection: $viewModel.filter) {
                                ForEach(ChangeFilter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .frame(width: 140)
                            Spacer(minLength: 12)
                            Text("\(viewModel.filteredChanges.count) shown")
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Search paths", text: $viewModel.searchText)
                                    .textFieldStyle(.roundedBorder)
                                Picker("Filter", selection: $viewModel.filter) {
                                    ForEach(ChangeFilter.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .frame(minWidth: 120)
                            }
                            Text("\(viewModel.filteredChanges.count) shown")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ResultsTable(viewModel: viewModel)
                case .folderImpact:
                    FolderImpactView(comparison: comparison) { impact in
                        viewModel.revealFolderImpactInFinder(impact)
                    }
                }
            } else {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView("No comparison yet", systemImage: "arrow.left.and.right", description: Text("Choose two snapshots to begin."))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No comparison yet")
                            .font(.headline)
                        Text("Choose two snapshots to begin.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
        }
        .padding()
    }
}

private struct ComparisonWarningsView: View {
    let warnings: [String]
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Comparison may be incomplete", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Dismiss warning", systemImage: "xmark") {
                        isDismissed = true
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Dismiss comparison warning")
                }

                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Comparison warning")
            .onChange(of: warnings) { _ in
                isDismissed = false
            }
        }
    }
}


private enum ComparisonResultsSection: String, CaseIterable, Identifiable {
    case changes = "All changes"
    case folderImpact = "Folder impact"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .changes: return "list.bullet.rectangle"
        case .folderImpact: return "chart.bar.xaxis"
        }
    }
}

struct SummaryHeader: View {
    let summary: ComparisonSummary

    var body: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "Added", value: "\(summary.addedCount)", detail: ByteCountFormatter.string(fromByteCount: Int64(summary.logicalBytesAdded), countStyle: .file), color: .green, icon: "plus")
            SummaryCard(title: "Removed", value: "\(summary.removedCount)", detail: ByteCountFormatter.string(fromByteCount: Int64(summary.logicalBytesRemoved), countStyle: .file), color: .red, icon: "minus")
            SummaryCard(title: "Modified", value: "\(summary.modifiedCount)", detail: ByteCountFormatter.string(fromByteCount: Int64(summary.logicalBytesModified), countStyle: .file), color: .orange, icon: "pencil")
            SummaryCard(title: "Folders", value: "\(summary.folderChangeCount)", detail: "Contents changed", color: .purple, icon: "folder")
            SummaryCard(title: "Scan duration", value: summary.duration.formatted(.number.precision(.fractionLength(1))) + "s", detail: "Elapsed time", color: .blue, icon: "timer")
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let detail: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).foregroundStyle(color)
            Text(value).font(.title2.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SizeDifferenceLabel: View {
    let difference: Int64

    var body: some View {
        Text(label)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var label: String {
        difference == 0 ? "0 bytes" : formatSignedBytes(difference)
    }

    private var color: Color {
        switch difference {
        case let value where value > 0: return .green
        case let value where value < 0: return .red
        default: return .secondary
        }
    }

    private func formatSignedBytes(_ bytes: Int64) -> String {
        (bytes > 0 ? "+" : "") + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct ChartSummary: View {
    let summary: ComparisonSummary
    private var data: [(String, UInt64)] { [("Added", summary.logicalBytesAdded), ("Removed", summary.logicalBytesRemoved), ("Modified", summary.logicalBytesModified)] }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Logical byte changes").font(.headline)
            Text("File-size totals. These values do not represent physical disk space used by APFS or hard links.")
                .font(.caption).foregroundStyle(.secondary)
            Chart(data, id: \.0) { entry in
                BarMark(x: .value("Logical bytes", entry.1), y: .value("Change", entry.0))
                    .foregroundStyle(by: .value("Change", entry.0))
            }
            .frame(height: 120)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Logical byte changes")
            .accessibilityValue(accessibilitySummary)
        }
        .padding(.vertical, 4)
    }

    private var accessibilitySummary: String {
        data.map { label, bytes in
            "\(label): \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
        }
        .joined(separator: ", ")
    }
}

private struct FolderImpactView: View {
    let comparison: SnapshotComparison
    let revealInFinder: (FolderImpact) -> Void
    @State private var ranking: FolderImpactRanking = .largestChange
    @State private var limit = 10
    @State private var selectedImpact: String?
    @State private var sortOrder: [KeyPathComparator<FolderImpact>] = [
        KeyPathComparator(\.absoluteLogicalChange, order: .reverse)
    ]

    private var impacts: [FolderImpact] {
        comparison.topFolderImpacts(limit: limit, rankedBy: ranking)
    }

    private var displayedImpacts: [FolderImpact] {
        var sorted = impacts
        sorted.sort(using: sortOrder)
        return sorted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Top changing folders")
                        .font(.title2.bold())
                    Text("Cumulative logical sizes include each folder's descendants. They do not represent physical APFS storage usage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Rank by", selection: $ranking) {
                    ForEach(FolderImpactRanking.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 230)
                Picker("Show", selection: $limit) {
                    ForEach([10, 25, 50, 100], id: \.self) { count in
                        Text("Top \(count)").tag(count)
                    }
                }
                .frame(width: 145)
                Spacer()
            }

            if impacts.isEmpty {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView(
                        "No folder size impact",
                        systemImage: "folder",
                        description: Text("No folders have a logical size change for this ranking.")
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No folder size impact")
                            .font(.headline)
                        Text("No folders have a logical size change for this ranking.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                FolderImpactTable(
                    impacts: displayedImpacts,
                    selectedImpact: $selectedImpact,
                    sortOrder: $sortOrder
                )
                .contextMenu {
                    if let selectedImpact,
                       let impact = displayedImpacts.first(where: { $0.id == selectedImpact }) {
                        Button("Reveal in Finder", systemImage: "folder") {
                            revealInFinder(impact)
                        }
                    }
                }
            }
        }
    }
}

private struct FolderImpactTable: View {
    let impacts: [FolderImpact]
    @Binding var selectedImpact: String?
    @Binding var sortOrder: [KeyPathComparator<FolderImpact>]

    var body: some View {
        Table(impacts, selection: $selectedImpact, sortOrder: $sortOrder) {
            TableColumn("#") { impact in
                Text(rank(for: impact), format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(32)
            TableColumn("Folder", sortUsing: KeyPathComparator(\.relativePath)) { impact in
                Label(impact.relativePath, systemImage: "folder")
                    .lineLimit(1)
                    .help(impact.relativePath)
            }
            .width(min: 240, ideal: 420)
            TableColumn("Before", sortUsing: KeyPathComparator(\.oldLogicalSize)) { impact in
                Text(formatBytes(impact.oldLogicalSize))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("After", sortUsing: KeyPathComparator(\.newLogicalSize)) { impact in
                Text(formatBytes(impact.newLogicalSize))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            TableColumn("Increase", sortUsing: KeyPathComparator(\.logicalBytesIncreased)) { impact in
                impactAmount(impact.logicalBytesIncreased, color: .green)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Decrease", sortUsing: KeyPathComparator(\.logicalBytesDecreased)) { impact in
                impactAmount(impact.logicalBytesDecreased, color: .red)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Difference", sortUsing: KeyPathComparator(\.logicalSizeDifference)) { impact in
                Text(formatSignedBytes(impact.logicalSizeDifference))
                    .monospacedDigit()
                    .foregroundStyle(impact.logicalSizeDifference >= 0 ? .green : .red)
            }
            .width(min: 95, ideal: 115)
        }
    }

    private func rank(for impact: FolderImpact) -> Int {
        (impacts.firstIndex(of: impact) ?? 0) + 1
    }

    @ViewBuilder
    private func impactAmount(_ bytes: UInt64, color: Color) -> some View {
        if bytes == 0 {
            Text("-")
                .foregroundStyle(.tertiary)
        } else {
            Text(formatBytes(bytes))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private func formatSignedBytes(_ bytes: Int64) -> String {
        bytes == 0 ? "0 bytes" : (bytes > 0 ? "+" : "") + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ResultsTable: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Table(viewModel.filteredChanges, selection: $viewModel.selectedChangeID, sortOrder: $viewModel.sortOrder) {
            TableColumn("Change type", value: \.kind.rawValue) { change in
                Label(change.kind.rawValue, systemImage: change.kind.systemImage)
            }
            TableColumn("File name", value: \.fileName) { change in Text(change.fileName) }
            TableColumn("Relative path", value: \.relativePath) { change in Text(change.relativePath).textSelection(.enabled) }
            TableColumn("Old size", sortUsing: KeyPathComparator(\.oldSizeForSorting)) { change in Text(change.oldSize.map(formatBytes) ?? "-").monospacedDigit() }
            TableColumn("New size", sortUsing: KeyPathComparator(\.newSizeForSorting)) { change in Text(change.newSize.map(formatBytes) ?? "-").monospacedDigit() }
            TableColumn("Difference", value: \.sizeDifference) { change in
                SizeDifferenceLabel(difference: change.sizeDifference)
            }
            TableColumn("Old modified", sortUsing: KeyPathComparator(\.oldModificationDateForSorting)) { change in Text(change.oldMetadata?.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "-") }
            TableColumn("New modified", sortUsing: KeyPathComparator(\.newModificationDateForSorting)) { change in Text(change.newMetadata?.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "-") }
        }
        .contextMenu {
            Button("Reveal in Finder", systemImage: "folder") { viewModel.revealSelectedInFinder() }
        }
        .safeAreaInset(edge: .bottom) {
            if let change = viewModel.selectedChange() {
                InspectorView(change: change)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.regularMaterial)
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
    private func formatSignedBytes(_ bytes: Int64) -> String { bytes == 0 ? "0 bytes" : (bytes > 0 ? "+" : "") + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct InspectorView: View {
    let change: FileChange
    var body: some View {
        HStack(alignment: .top) {
            Label(change.kind.rawValue, systemImage: change.kind.systemImage).font(.headline)
            VStack(alignment: .leading) {
                Text(change.relativePath).font(.callout.monospaced()).textSelection(.enabled)
                Text("Old: \(change.oldMetadata.map { $0.itemType.rawValue } ?? "not present")    New: \(change.newMetadata.map { $0.itemType.rawValue } ?? "not present")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
