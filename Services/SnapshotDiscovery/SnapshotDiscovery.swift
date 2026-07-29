import Foundation

protocol SnapshotDiscoveryStrategy: Sendable {
    func discover(on volume: URL) async throws -> [BackupSnapshot]
}

struct VolumeValidation: Sendable {
    let isCandidate: Bool
    let detail: String
    let requiresSnapshotVerification: Bool
}

struct TimeMachineSnapshotDiscovery: SnapshotDiscoveryStrategy {
    func validate(volume: URL) -> VolumeValidation {
        let fileManager = FileManager.default
        let standardizedVolume = volume.standardizedFileURL
        let values = try? standardizedVolume.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeIsReadOnlyKey,
            .volumeURLKey
        ])
        let volumeRoot = values?.allValues[.volumeURLKey] as? URL
        guard standardizedVolume.isFileURL,
              volumeRoot?.standardizedFileURL == standardizedVolume,
              fileManager.isReadableFile(atPath: standardizedVolume.path) else {
            return VolumeValidation(
                isCandidate: false,
                detail: "Choose the root of a mounted volume so Time Machine can be verified safely.",
                requiresSnapshotVerification: false
            )
        }

        let volumeName = values?.volumeName ?? standardizedVolume.lastPathComponent
        if let evidence = Self.timeMachineEvidence(at: standardizedVolume, volumeName: volumeName) {
            return VolumeValidation(isCandidate: true, detail: evidence, requiresSnapshotVerification: false)
        }

        return VolumeValidation(
            isCandidate: true,
            detail: "This mounted volume will be verified with read-only Time Machine discovery.",
            requiresSnapshotVerification: true
        )
    }

    func isSidebarCandidate(volume: URL) -> Bool {
        let standardizedVolume = volume.standardizedFileURL
        guard let values = try? standardizedVolume.resourceValues(forKeys: [.volumeNameKey, .volumeURLKey]),
              let volumeRoot = values.allValues[.volumeURLKey] as? URL,
              volumeRoot.standardizedFileURL == standardizedVolume else {
            return false
        }

        let volumeName = values.volumeName ?? standardizedVolume.lastPathComponent
        return Self.timeMachineEvidence(at: standardizedVolume, volumeName: volumeName) != nil
    }

    static func timeMachineEvidence(at volume: URL, volumeName: String) -> String? {
        let fileManager = FileManager.default
        let markers: [(String, String)] = [
            ("Backups.backupdb", "Found a Backups.backupdb directory"),
            (".timemachine", "Found the APFS .timemachine directory"),
            (".com.apple.timemachine.donotpresent", "Found the APFS Time Machine marker")
        ]
        for (path, description) in markers where fileManager.fileExists(atPath: volume.appendingPathComponent(path).path) {
            return "\(description) on \(volumeName)."
        }
        if volumeName.localizedCaseInsensitiveContains("time machine") {
            return "The volume name suggests a Time Machine destination. Snapshot discovery will verify it."
        }
        return nil
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
        let stdout = try await SystemCommandRunner().run(
            "/usr/bin/tmutil",
            arguments: ["listbackups", "-d", volume.path, "-m"]
        )
        return stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

}
