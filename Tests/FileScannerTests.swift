import Foundation
import XCTest
@testable import TimeVault

final class FileScannerTests: XCTestCase {
    @MainActor
    func testNewerComparisonCannotBeOverwrittenByStaleResult() async throws {
        let viewModel = AppViewModel(
            comparisonOperation: { older, newer, _ in
                let delay: UInt64 = newer.identifier == "first" ? 150_000_000 : 20_000_000
                await nonCancellableDelay(nanoseconds: delay)
                return emptyComparison(older: older, newer: newer)
            },
            performInitialRefresh: false
        )
        let older = testSnapshot(identifier: "older", timestamp: 100)
        let first = testSnapshot(identifier: "first", timestamp: 200)
        let second = testSnapshot(identifier: "second", timestamp: 300)

        viewModel.olderSnapshot = older
        viewModel.newerSnapshot = first
        viewModel.compareSnapshots()
        viewModel.newerSnapshot = second
        viewModel.compareSnapshots()

        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(viewModel.comparison?.newerSnapshot.identifier, "second")
        XCTAssertEqual(viewModel.section, .comparison)
        XCTAssertFalse(viewModel.isComparing)
    }

    @MainActor
    func testCancelledComparisonCannotPublishLateResult() async throws {
        let operationStarted = expectation(description: "Comparison started")
        let viewModel = AppViewModel(
            comparisonOperation: { older, newer, _ in
                operationStarted.fulfill()
                await nonCancellableDelay(nanoseconds: 100_000_000)
                return emptyComparison(older: older, newer: newer)
            },
            performInitialRefresh: false
        )
        viewModel.olderSnapshot = testSnapshot(identifier: "older", timestamp: 100)
        viewModel.newerSnapshot = testSnapshot(identifier: "newer", timestamp: 200)
        viewModel.compareSnapshots()

        await fulfillment(of: [operationStarted], timeout: 1)
        viewModel.cancelComparison()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertNil(viewModel.comparison)
        XCTAssertFalse(viewModel.isComparing)
        XCTAssertNil(viewModel.progress)
    }

    func testScannerForwardsIncompleteScanWarnings() async throws {
        let scanner = FileScanner(fileSystem: WarningFileSystem())
        var finishedResult: FileScanResult?

        for try await event in scanner.events(for: URL(fileURLWithPath: "/fixture"), label: "Fixture") {
            if case .finished(let result) = event {
                finishedResult = result
            }
        }

        XCTAssertEqual(finishedResult?.warnings, ["The scan skipped 1 item."])
    }

    func testComparisonLabelsWarningsBySnapshot() async throws {
        let service = ComparisonService(
            scanner: FileScanner(fileSystem: SnapshotWarningFileSystem()),
            engine: ComparisonEngine()
        )
        let older = BackupSnapshot(
            date: Date(timeIntervalSince1970: 100),
            backupVolume: "Fixture",
            machineName: nil,
            url: URL(fileURLWithPath: "/older"),
            identifier: "older"
        )
        let newer = BackupSnapshot(
            date: Date(timeIntervalSince1970: 200),
            backupVolume: "Fixture",
            machineName: nil,
            url: URL(fileURLWithPath: "/newer"),
            identifier: "newer"
        )

        let comparison = try await service.compare(
            olderSnapshot: older,
            newerSnapshot: newer,
            progress: { _ in }
        )

        XCTAssertEqual(comparison.warnings, ["Older snapshot: The scan skipped protected.txt."])
    }

    func testCancellationStopsScan() async throws {
        let scanStarted = expectation(description: "Scan started")
        let scanStopped = expectation(description: "Scan stopped")
        let scanner = FileScanner(fileSystem: BlockingFileSystem(
            started: { scanStarted.fulfill() },
            stopped: { scanStopped.fulfill() }
        ))
        let task = Task {
            do {
                for try await _ in scanner.events(for: URL(fileURLWithPath: "/fixture"), label: "Fixture") { }
            } catch {
                XCTAssertEqual((error as? AppError)?.errorDescription, AppError.comparisonCancelled.errorDescription)
            }
        }

        await fulfillment(of: [scanStarted], timeout: 1)
        task.cancel()
        await fulfillment(of: [scanStopped], timeout: 1)
        await task.value
        XCTAssertTrue(task.isCancelled)
    }
}

private func nonCancellableDelay(nanoseconds: UInt64) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
            continuation.resume()
        }
    }
}

private func testSnapshot(identifier: String, timestamp: TimeInterval) -> BackupSnapshot {
    BackupSnapshot(
        date: Date(timeIntervalSince1970: timestamp),
        backupVolume: "Fixture",
        machineName: nil,
        url: URL(fileURLWithPath: "/\(identifier)"),
        identifier: identifier
    )
}

private func emptyComparison(older: BackupSnapshot, newer: BackupSnapshot) -> SnapshotComparison {
    SnapshotComparison(
        olderSnapshot: older,
        newerSnapshot: newer,
        changes: [],
        folderImpacts: [],
        summary: ComparisonSummary(
            addedCount: 0,
            removedCount: 0,
            modifiedCount: 0,
            folderChangeCount: 0,
            logicalBytesAdded: 0,
            logicalBytesRemoved: 0,
            logicalBytesModified: 0,
            duration: 0
        ),
        warnings: []
    )
}

private struct WarningFileSystem: FileSystem {
    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> FileScanResult {
        FileScanResult(records: [], warnings: ["The scan skipped 1 item."])
    }
}

private struct SnapshotWarningFileSystem: FileSystem {
    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> FileScanResult {
        let warnings = root.lastPathComponent == "older" ? ["The scan skipped protected.txt."] : []
        return FileScanResult(records: [], warnings: warnings)
    }
}

private struct BlockingFileSystem: FileSystem {
    let started: @Sendable () -> Void
    let stopped: @Sendable () -> Void

    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> FileScanResult {
        defer { stopped() }
        started()
        progress(1)
        while true {
            try Task.checkCancellation()
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
}
