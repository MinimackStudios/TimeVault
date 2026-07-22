import Charts
import SwiftUI

struct ComparisonResultsView: View {
    @ObservedObject var viewModel: AppViewModel

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
                ChartSummary(summary: comparison.summary)
                HStack {
                    TextField("Search paths", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    Picker("Filter", selection: $viewModel.filter) {
                        ForEach(ChangeFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 140)
                    Spacer()
                    Text("\(viewModel.filteredChanges.count) shown").foregroundStyle(.secondary)
                }
                ResultsTable(viewModel: viewModel)
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

struct SummaryHeader: View {
    let summary: ComparisonSummary

    var body: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "Added", value: "\(summary.addedCount)", detail: ByteCountFormatter.string(fromByteCount: Int64(summary.logicalBytesAdded), countStyle: .file), color: .green, icon: "plus")
            SummaryCard(title: "Removed", value: "\(summary.removedCount)", detail: ByteCountFormatter.string(fromByteCount: Int64(summary.logicalBytesRemoved), countStyle: .file), color: .red, icon: "minus")
            SummaryCard(title: "Modified", value: "\(summary.modifiedCount)", detail: ByteCountFormatter.string(fromByteCount: Int64(summary.logicalBytesModified), countStyle: .file), color: .orange, icon: "pencil")
            SummaryCard(title: "Folders", value: "\(summary.folderChangeCount)", detail: "Contents changed", color: .purple, icon: "folder")
            SummaryCard(title: "Scan duration", value: summary.duration.formatted(.number.precision(.fractionLength(1))) + "s", detail: "Logical bytes", color: .blue, icon: "timer")
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
        }
        .padding(.vertical, 4)
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
            TableColumn("Difference", value: \.sizeDifference) { change in Text(formatSignedBytes(change.sizeDifference)).monospacedDigit() }
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
