import Foundation

protocol SnapshotDiscoveryStrategy: Sendable {
    func discover(on volume: URL) async throws -> [BackupSnapshot]
}

struct VolumeValidation: Sendable {
    let isCandidate: Bool
    let detail: String
}

struct TimeMachineSnapshotDiscovery: SnapshotDiscoveryStrategy {
    func validate(volume: URL) -> VolumeValidation {
        let fileManager = FileManager.default
        let values = try? volume.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey, .volumeIsReadOnlyKey])
        let hasKnownDirectory = fileManager.fileExists(atPath: volume.appendingPathComponent("Backups.backupdb").path)
        let volumeName = values?.volumeName ?? volume.lastPathComponent
        if hasKnownDirectory { return VolumeValidation(isCandidate: true, detail: "Found a Backups.backupdb directory on \(volumeName).") }
        if volumeName.localizedCaseInsensitiveContains("time machine") {
            return VolumeValidation(isCandidate: true, detail: "The volume name suggests a Time Machine destination. Snapshot discovery will verify it.")
        }
        return VolumeValidation(isCandidate: false, detail: "No recognized Time Machine directory was found on \(volumeName).")
    }

    func discover(on volume: URL) async throws -> [BackupSnapshot] {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: volume.path) else { throw AppError.permissionDenied(volume) }
        var snapshots = discoverKnownDirectories(on: volume)
        if snapshots.isEmpty {
            snapshots = try await discoverWithTMUtil(on: volume)
        }
        guard !snapshots.isEmpty else { throw AppError.noSnapshotsFound }
        return snapshots.sorted { $0.date < $1.date }
    }

    private func discoverKnownDirectories(on volume: URL) -> [BackupSnapshot] {
        let fileManager = FileManager.default
        let base = volume.appendingPathComponent("Backups.backupdb", isDirectory: true)
        guard let machines = try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [BackupSnapshot] = []
        for machine in machines where (try? machine.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let children = (try? fileManager.contentsOfDirectory(at: machine, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard let date = parseDate(from: child.lastPathComponent) else { continue }
                result.append(BackupSnapshot(date: date, backupVolume: volume.lastPathComponent, machineName: machine.lastPathComponent, url: child, identifier: child.lastPathComponent))
            }
        }
        return result
    }

    private func discoverWithTMUtil(on volume: URL) async throws -> [BackupSnapshot] {
        let result = try await TMUtilRunner().listBackups(on: volume)
        return result.compactMap { path in
            let url = URL(fileURLWithPath: path)
            let timestampComponent = url.lastPathComponent.hasSuffix(".backup") ? url.lastPathComponent : url.deletingLastPathComponent().lastPathComponent
            guard let date = parseDate(from: timestampComponent) else { return nil }
            return BackupSnapshot(date: date, backupVolume: volume.lastPathComponent, machineName: nil, url: url, identifier: path)
        }
    }

    private func parseDate(from value: String) -> Date? {
        let normalizedValue = value.hasSuffix(".backup") ? String(value.dropLast(".backup".count)) : value
        let formats = ["yyyy-MM-dd-HHmmss", "yyyy-MM-dd-HH:mm:ss", "yyyy-MM-dd HH-mm-ss"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: normalizedValue) { return date }
        }
        return ISO8601DateFormatter().date(from: normalizedValue)
    }
}

struct TMUtilRunner: Sendable {
    func listBackups(on volume: URL) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
            process.arguments = ["listbackups", "-d", volume.path, "-m"]
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            do {
                try process.run()
                process.waitUntilExit()
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: AppError.tmutilFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }
                let paths = stdout.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                continuation.resume(returning: paths)
            } catch {
                continuation.resume(throwing: AppError.tmutilFailed(error.localizedDescription))
            }
        }
    }

}
