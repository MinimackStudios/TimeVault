import Foundation

struct LocalSnapshot: Identifiable, Hashable, Sendable {
    let name: String
    let date: Date?
    let volumeName: String

    var id: String { name }
}

struct SystemOverview: Sendable {
    let backupActivity: BackupActivity
    let lastBackupPath: String?
    let startupVolumeName: String
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let localSnapshotCount: Int
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
