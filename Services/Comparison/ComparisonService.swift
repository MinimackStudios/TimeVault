import Foundation

struct ComparisonService: Sendable {
    let scanner: FileScanner
    let engine: ComparisonEngine

    func compare(olderSnapshot: BackupSnapshot, newerSnapshot: BackupSnapshot, progress: @escaping @Sendable (ScanProgress) async -> Void) async throws -> SnapshotComparison {
        let started = Date()
        let reportProgress: @Sendable (ScanProgress) async -> Void = { value in
            await progress(ScanProgress(
                phase: value.phase,
                rootName: value.rootName,
                itemsScanned: value.itemsScanned,
                estimatedItemCount: value.estimatedItemCount,
                elapsedTime: max(Date().timeIntervalSince(started), value.elapsedTime),
                itemsPerSecond: value.itemsPerSecond,
                startedAt: started
            ))
        }
        let coordinator = ScanCompletionCoordinator(labels: ["Older snapshot", "Newer snapshot"])
        async let olderScan = scan(snapshot: olderSnapshot, label: "Older snapshot", coordinator: coordinator, progress: reportProgress)
        async let newerScan = scan(snapshot: newerSnapshot, label: "Newer snapshot", coordinator: coordinator, progress: reportProgress)
        let (old, new) = try await (olderScan, newerScan)
        try Task.checkCancellation()
        let comparison = try await engine.compare(
            older: old.records,
            newer: new.records,
            olderSnapshot: olderSnapshot,
            newerSnapshot: newerSnapshot,
            duration: 0,
            progress: reportProgress
        )
        let summary = ComparisonSummary(
            addedCount: comparison.summary.addedCount,
            removedCount: comparison.summary.removedCount,
            modifiedCount: comparison.summary.modifiedCount,
            folderChangeCount: comparison.summary.folderChangeCount,
            logicalBytesAdded: comparison.summary.logicalBytesAdded,
            logicalBytesRemoved: comparison.summary.logicalBytesRemoved,
            logicalBytesModified: comparison.summary.logicalBytesModified,
            duration: Date().timeIntervalSince(started)
        )
        return SnapshotComparison(
            olderSnapshot: comparison.olderSnapshot,
            newerSnapshot: comparison.newerSnapshot,
            changes: comparison.changes,
            folderImpacts: comparison.folderImpacts,
            summary: summary,
            warnings: old.warnings.map { "Older snapshot: \($0)" }
                + new.warnings.map { "Newer snapshot: \($0)" }
                + comparison.warnings
        )
    }

    private func scan(snapshot: BackupSnapshot, label: String, coordinator: ScanCompletionCoordinator, progress: @escaping @Sendable (ScanProgress) async -> Void) async throws -> FileScanResult {
        var result = FileScanResult(records: [], warnings: [])
        for try await event in scanner.events(for: snapshot.url, label: label) {
            switch event {
            case .progress(let value):
                await coordinator.update(value)
                await progress(value)
            case .finished(let value):
                result = value
                await progress(coordinator.completedProgress(for: label))
            }
        }
        return result
    }
}

private actor ScanCompletionCoordinator {
    private let labels: Set<String>
    private var completedLabels: Set<String> = []
    private var latestProgress: [String: ScanProgress] = [:]

    init(labels: [String]) {
        self.labels = Set(labels)
    }

    func update(_ progress: ScanProgress) {
        latestProgress[progress.rootName] = progress
    }

    func completedProgress(for label: String) -> ScanProgress {
        completedLabels.insert(label)
        let current = latestProgress[label] ?? ScanProgress(
            phase: "Scanning",
            rootName: label,
            itemsScanned: 0,
            estimatedItemCount: nil,
            elapsedTime: 0,
            itemsPerSecond: 0,
            startedAt: nil
        )

        if let waitingFor = labels.subtracting(completedLabels).sorted().first {
            return ScanProgress(
                phase: "Waiting for " + waitingFor,
                rootName: label,
                itemsScanned: current.itemsScanned,
                estimatedItemCount: current.estimatedItemCount,
                elapsedTime: current.elapsedTime,
                itemsPerSecond: current.itemsPerSecond,
                startedAt: current.startedAt
            )
        }

        let totalItems = latestProgress.values.reduce(0) { $0 + $1.itemsScanned }
        let elapsedTime = latestProgress.values.map(\.elapsedTime).max() ?? current.elapsedTime
        let rate = latestProgress.values.reduce(0) { $0 + $1.itemsPerSecond }
        return ScanProgress(
            phase: "Preparing comparison",
            rootName: "Both snapshots",
            itemsScanned: totalItems,
            estimatedItemCount: nil,
            elapsedTime: elapsedTime,
            itemsPerSecond: rate,
            startedAt: current.startedAt
        )
    }
}
