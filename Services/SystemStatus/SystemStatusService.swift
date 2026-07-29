import Foundation

struct SystemStatusService: Sendable {
    private let commandRunner: any SystemCommandRunning

    init(commandRunner: any SystemCommandRunning = SystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func loadDashboard() async -> (overview: SystemOverview, localSnapshots: [LocalSnapshot]) {
        async let activity = backupActivity()
        async let lastBackupPath = lastBackup()
        async let localSnapshots = discoverLocalSnapshots()

        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ])

        let (resolvedActivity, resolvedLastBackupPath, snapshotResult) = await (activity, lastBackupPath, localSnapshots)
        let overview = SystemOverview(
            backupActivity: resolvedActivity,
            lastBackupPath: resolvedLastBackupPath,
            startupVolumeName: values?.volumeName ?? "Startup disk",
            totalCapacity: values?.volumeTotalCapacity.map(Int64.init),
            availableCapacity: values?.volumeAvailableCapacity.map(Int64.init),
            localSnapshotStatus: snapshotResult.status,
            refreshedAt: Date()
        )
        return (overview, snapshotResult.snapshots)
    }

    func discoverLocalSnapshots() async -> LocalSnapshotDiscoveryResult {
        let output: String
        do {
            output = try await commandRunner.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])
        } catch is CancellationError {
            return LocalSnapshotDiscoveryResult(status: .unavailable, snapshots: [])
        } catch {
            return LocalSnapshotDiscoveryResult(status: .failed, snapshots: [])
        }
        let volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Startup disk"
        let snapshots = Self.snapshotNames(in: output)
            .map { LocalSnapshot(name: $0, date: Self.snapshotDate(in: $0), volumeName: volumeName) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return LocalSnapshotDiscoveryResult(status: .loaded(snapshots.count), snapshots: snapshots)
    }

    private func backupActivity() async -> BackupActivity {
        guard let output = try? await commandRunner.run("/usr/bin/tmutil", arguments: ["status"]) else {
            return .unavailable
        }
        if output.range(of: "Running = 1", options: .caseInsensitive) != nil { return .running }
        if output.range(of: "Running = 0", options: .caseInsensitive) != nil { return .idle }
        return .unavailable
    }

    private func lastBackup() async -> String? {
        guard let output = try? await commandRunner.run("/usr/bin/tmutil", arguments: ["latestbackup"]) else {
            return nil
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func snapshotDate(in name: String) -> Date? {
        guard let range = name.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: String(name[range]))
    }

    static func snapshotNames(in output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { snapshotDate(in: $0) != nil }
    }

}

struct LocalSnapshotDiscoveryResult: Sendable {
    let status: LocalSnapshotDiscoveryStatus
    let snapshots: [LocalSnapshot]
}

protocol SystemCommandRunning: Sendable {
    func run(_ executablePath: String, arguments: [String]) async throws -> String
}

struct SystemCommandRunner: SystemCommandRunning, Sendable {
    func run(_ executablePath: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let controller = ProcessController(process: process)

        return try await withTaskCancellationHandler {
            do {
                try controller.start()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw AppError.tmutilFailed(error.localizedDescription)
            }

            let stdoutTask = Task.detached(priority: .utility) {
                output.fileHandleForReading.readDataToEndOfFile()
            }
            let stderrTask = Task.detached(priority: .utility) {
                error.fileHandleForReading.readDataToEndOfFile()
            }
            let terminationTask = Task.detached(priority: .utility) {
                process.waitUntilExit()
                return process.terminationStatus
            }

            let status = await terminationTask.value
            let stdoutData = await stdoutTask.value
            let stderrData = await stderrTask.value
            try Task.checkCancellation()

            guard status == 0 else {
                let message = String(data: stderrData, encoding: .utf8) ?? "Command failed."
                throw AppError.tmutilFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return String(data: stdoutData, encoding: .utf8) ?? ""
        } onCancel: {
            controller.cancel()
        }
    }
}

private final class ProcessController: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var isCancelled = false
    private var hasStarted = false

    init(process: Process) {
        self.process = process
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { throw CancellationError() }
        try process.run()
        hasStarted = true
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let shouldTerminate = hasStarted && process.isRunning
        lock.unlock()

        if shouldTerminate {
            process.terminate()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
