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

struct FolderImpact: Identifiable, Codable, Hashable, Sendable {
    let relativePath: String
    let oldLogicalSize: UInt64
    let newLogicalSize: UInt64

    var id: String { relativePath }
    var folderName: String { URL(fileURLWithPath: relativePath).lastPathComponent }

    var logicalSizeDifference: Int64 {
        if newLogicalSize >= oldLogicalSize {
            return Int64(clamping: newLogicalSize - oldLogicalSize)
        }
        return -Int64(clamping: oldLogicalSize - newLogicalSize)
    }

    var logicalBytesIncreased: UInt64 {
        newLogicalSize > oldLogicalSize ? newLogicalSize - oldLogicalSize : 0
    }

    var logicalBytesDecreased: UInt64 {
        oldLogicalSize > newLogicalSize ? oldLogicalSize - newLogicalSize : 0
    }

    var absoluteLogicalChange: UInt64 {
        max(logicalBytesIncreased, logicalBytesDecreased)
    }
}

enum FolderImpactRanking: String, CaseIterable, Identifiable, Sendable {
    case largestChange = "Largest changes"
    case largestIncrease = "Most added"
    case largestDecrease = "Most removed"

    var id: Self { self }

    fileprivate func score(for impact: FolderImpact) -> UInt64 {
        switch self {
        case .largestChange:
            return impact.absoluteLogicalChange
        case .largestIncrease:
            return impact.logicalBytesIncreased
        case .largestDecrease:
            return impact.logicalBytesDecreased
        }
    }
}

struct SnapshotComparison: Codable, Hashable, Sendable {
    let olderSnapshot: BackupSnapshot
    let newerSnapshot: BackupSnapshot
    let changes: [FileChange]
    let folderImpacts: [FolderImpact]
    let summary: ComparisonSummary
    let warnings: [String]

    func topFolderImpacts(limit: Int, rankedBy ranking: FolderImpactRanking) -> [FolderImpact] {
        guard limit > 0 else { return [] }
        return Array(
            folderImpacts
                .filter { ranking.score(for: $0) > 0 }
                .sorted { left, right in
                    let leftScore = ranking.score(for: left)
                    let rightScore = ranking.score(for: right)
                    if leftScore != rightScore { return leftScore > rightScore }
                    return left.relativePath.localizedStandardCompare(right.relativePath) == .orderedAscending
                }
                .prefix(limit)
        )
    }
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
