import Foundation

struct LocalSnapshot: Identifiable, Hashable, Sendable {
    let name: String
    let date: Date?
    let volumeName: String

    var id: String { name }
}

enum LocalSnapshotDiscoveryStatus: Equatable, Sendable {
    case loaded(Int)
    case unavailable
    case failed

    var count: Int? {
        if case .loaded(let count) = self { return count }
        return nil
    }

    var displayValue: String {
        count?.formatted() ?? "Unavailable"
    }

    var detail: String {
        switch self {
        case .loaded(let count):
            return count == 0 ? "No local snapshots found" : "On the startup disk"
        case .unavailable:
            return "Local snapshot status is unavailable"
        case .failed:
            return "Unable to determine local snapshot status"
        }
    }
}

struct SystemOverview: Sendable {
    let backupActivity: BackupActivity
    let lastBackupPath: String?
    let startupVolumeName: String
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let localSnapshotStatus: LocalSnapshotDiscoveryStatus
    let refreshedAt: Date

    var usedCapacity: Int64? {
        guard let totalCapacity, let availableCapacity else { return nil }
        return max(totalCapacity - availableCapacity, 0)
    }
}

enum BackupActivity: Equatable, Sendable {
    case running
    case idle
    case unavailable

    var title: String {
        switch self {
        case .running: "Backup in progress"
        case .idle: "Backup idle"
        case .unavailable: "Status unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .running: "arrow.triangle.2.circlepath.circle.fill"
        case .idle: "checkmark.circle.fill"
        case .unavailable: "questionmark.circle"
        }
    }
}
