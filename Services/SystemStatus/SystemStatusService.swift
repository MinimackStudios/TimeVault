import Foundation
import AppKit

struct SystemStatusService: Sendable {
    private let commandRunner = SystemCommandRunner()

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

        let (resolvedActivity, resolvedLastBackupPath, snapshots) = await (activity, lastBackupPath, localSnapshots)
        let overview = SystemOverview(
            backupActivity: resolvedActivity,
            lastBackupPath: resolvedLastBackupPath,
            startupVolumeName: values?.volumeName ?? "Startup disk",
            totalCapacity: values?.volumeTotalCapacity.map(Int64.init),
            availableCapacity: values?.volumeAvailableCapacity.map(Int64.init),
            localSnapshotCount: snapshots.count,
            refreshedAt: Date()
        )
        return (overview, snapshots)
    }

    func discoverLocalSnapshots() async -> [LocalSnapshot] {
        guard let output = try? await commandRunner.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"]) else {
            return []
        }
        let volumeName = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Startup disk"
        return Self.snapshotNames(in: output)
            .map { LocalSnapshot(name: $0, date: Self.snapshotDate(in: $0), volumeName: volumeName) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    @MainActor
    func browseLocalSnapshots() async throws {
        let workspace = NSWorkspace.shared
        guard workspace.open(URL(fileURLWithPath: "/")) else {
            throw LocalSnapshotBrowseError.finderUnavailable
        }
        try await Task.sleep(nanoseconds: 250_000_000)

        let applicationURL = URL(fileURLWithPath: "/System/Applications/Time Machine.app")
        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            throw LocalSnapshotBrowseError.timeMachineUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await workspace.openApplication(at: applicationURL, configuration: configuration)
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

enum LocalSnapshotBrowseError: LocalizedError {
    case finderUnavailable
    case timeMachineUnavailable

    var errorDescription: String? {
        switch self {
        case .finderUnavailable:
            "TimeVault could not open the startup disk in Finder."
        case .timeMachineUnavailable:
            "The Time Machine browser is unavailable on this Mac."
        }
    }
}

private struct SystemCommandRunner: Sendable {
    func run(_ executablePath: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Command failed."
                    continuation.resume(throwing: AppError.tmutilFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }
                continuation.resume(returning: String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
