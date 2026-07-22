import Foundation

struct ComparisonSummary: Codable, Hashable, Sendable {
    let addedCount: Int
    let removedCount: Int
    let modifiedCount: Int
    let folderChangeCount: Int
    let logicalBytesAdded: UInt64
    let logicalBytesRemoved: UInt64
    let logicalBytesModified: UInt64
    let duration: TimeInterval

    var totalChangedCount: Int { addedCount + removedCount + modifiedCount }
}

struct SnapshotComparison: Codable, Hashable, Sendable {
    let olderSnapshot: BackupSnapshot
    let newerSnapshot: BackupSnapshot
    let changes: [FileChange]
    let summary: ComparisonSummary
    let warnings: [String]
}

struct ScanProgress: Sendable {
    let phase: String
    let rootName: String
    let itemsScanned: Int
    let estimatedItemCount: Int?
    let elapsedTime: TimeInterval
    let itemsPerSecond: Double
    let startedAt: Date?
}
