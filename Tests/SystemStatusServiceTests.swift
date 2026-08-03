import XCTest
@testable import TimeVault

final class SystemStatusServiceTests: XCTestCase {
    func testTimeMachineEvidenceRecognizesAPFSMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeVaultValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appendingPathComponent(".com.apple.timemachine.donotpresent"))

        let evidence = TimeMachineSnapshotDiscovery.timeMachineEvidence(
            at: directory,
            volumeName: "Archive"
        )

        XCTAssertEqual(evidence, "Found the APFS Time Machine marker on Archive.")
    }

    func testVolumeValidationRejectsFoldersInsideAVolume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeVaultValidation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let validation = TimeMachineSnapshotDiscovery().validate(volume: directory)

        XCTAssertFalse(validation.isCandidate)
        XCTAssertFalse(validation.requiresSnapshotVerification)
    }

    func testEmptySuccessfulDiscoveryReportsLoadedZero() async {
        let result = await SystemStatusService(
            commandRunner: StubCommandRunner(result: .success(""))
        ).discoverLocalSnapshots()

        XCTAssertEqual(result.status, .loaded(0))
        XCTAssertFalse(result.status.hasSnapshots)
        XCTAssertTrue(result.snapshots.isEmpty)
    }

    func testSuccessfulDiscoveryReportsSnapshotCount() async {
        let output = """
        com.apple.TimeMachine.2026-07-23-143015.local
        com.apple.TimeMachine.2026-07-23-175646.local
        """
        let result = await SystemStatusService(
            commandRunner: StubCommandRunner(result: .success(output))
        ).discoverLocalSnapshots()

        XCTAssertEqual(result.status, .loaded(2))
        XCTAssertTrue(result.status.hasSnapshots)
        XCTAssertEqual(result.snapshots.count, 2)
    }

    func testFailedDiscoveryReportsFailureInsteadOfZero() async {
        let result = await SystemStatusService(
            commandRunner: StubCommandRunner(result: .failure(.commandFailed))
        ).discoverLocalSnapshots()

        XCTAssertEqual(result.status, .failed)
        XCTAssertNil(result.status.count)
        XCTAssertFalse(result.status.hasSnapshots)
        XCTAssertTrue(result.snapshots.isEmpty)
    }

    func testDashboardPreservesFailedDiscoveryStatus() async {
        let dashboard = await SystemStatusService(
            commandRunner: StubCommandRunner(result: .failure(.commandFailed))
        ).loadDashboard()

        XCTAssertEqual(dashboard.overview.localSnapshotStatus, .failed)
        XCTAssertNil(dashboard.overview.localSnapshotStatus.count)
        XCTAssertTrue(dashboard.localSnapshots.isEmpty)
    }

    func testIdleDashboardReportsDisconnectedWithoutMountedBackupDrive() {
        let activity = BackupActivity.idle.resolvedForDashboard(hasMountedBackupDrive: false)

        XCTAssertEqual(activity, .disconnected)
        XCTAssertEqual(activity.title, "No backup drive connected")
        XCTAssertEqual(activity.systemImage, "externaldrive.badge.xmark")
    }

    func testUnavailableDashboardReportsDisconnectedWithoutMountedBackupDrive() {
        XCTAssertEqual(
            BackupActivity.unavailable.resolvedForDashboard(hasMountedBackupDrive: false),
            .disconnected
        )
    }

    func testRunningBackupRemainsVisibleWithoutDiscoveredMountedDrive() {
        XCTAssertEqual(
            BackupActivity.running.resolvedForDashboard(hasMountedBackupDrive: false),
            .running
        )
    }

    func testIdleDashboardRemainsIdleWithMountedBackupDrive() {
        XCTAssertEqual(
            BackupActivity.idle.resolvedForDashboard(hasMountedBackupDrive: true),
            .idle
        )
    }

    func testCommandRunnerDrainsLargeStandardOutput() async throws {
        let output = try await SystemCommandRunner().run(
            "/bin/sh",
            arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' x"]
        )

        XCTAssertEqual(output.count, 200_000)
    }

    func testCommandRunnerDrainsLargeStandardError() async throws {
        let output = try await SystemCommandRunner().run(
            "/bin/sh",
            arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' e >&2; printf done"]
        )

        XCTAssertEqual(output, "done")
    }

    func testCommandRunnerTerminatesProcessWhenCancelled() async throws {
        let task = Task {
            try await SystemCommandRunner().run("/bin/sleep", arguments: ["10"])
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCommandRunnerReportsStandardErrorOnFailure() async throws {
        do {
            _ = try await SystemCommandRunner().run(
                "/bin/sh",
                arguments: ["-c", "printf 'tmutil failed' >&2; exit 7"]
            )
            XCTFail("Expected command failure")
        } catch let error as AppError {
            XCTAssertTrue(error.errorDescription?.contains("tmutil failed") == true)
        }
    }

    func testParsesTimeMachineLocalSnapshotDate() {
        let date = SystemStatusService.snapshotDate(in: "com.apple.TimeMachine.2026-07-23-143015.local")

        let components = date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) }
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 7)
        XCTAssertEqual(components?.day, 23)
        XCTAssertEqual(components?.hour, 14)
        XCTAssertEqual(components?.minute, 30)
        XCTAssertEqual(components?.second, 15)
    }

    func testParsesBackupDateFromMountedPath() {
        let path = "/Volumes/.timemachine/machine/2026-07-23-175646.backup/2026-07-23-175646.backup"
        let date = SystemStatusService.snapshotDate(in: path)

        let components = date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) }
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 7)
        XCTAssertEqual(components?.day, 23)
        XCTAssertEqual(components?.hour, 17)
        XCTAssertEqual(components?.minute, 56)
        XCTAssertEqual(components?.second, 46)
    }

    func testIgnoresNamesWithoutTimestamp() {
        XCTAssertNil(SystemStatusService.snapshotDate(in: "com.apple.TimeMachine.local"))
    }

    func testIgnoresTMUtilHeaderWhenParsingSnapshotNames() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-07-23-143015.local
        """

        XCTAssertEqual(
            SystemStatusService.snapshotNames(in: output),
            ["com.apple.TimeMachine.2026-07-23-143015.local"]
        )
    }

}

private enum StubCommandError: Error, Sendable {
    case commandFailed
}

private struct StubCommandRunner: SystemCommandRunning {
    let result: Result<String, StubCommandError>

    func run(_ executablePath: String, arguments: [String]) async throws -> String {
        try result.get()
    }
}
