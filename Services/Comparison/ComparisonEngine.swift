import Foundation

struct ComparisonEngine: Sendable {
    func compare(older: [FileMetadata], newer: [FileMetadata], olderSnapshot: BackupSnapshot, newerSnapshot: BackupSnapshot, duration: TimeInterval, progress: @escaping @Sendable (ScanProgress) async -> Void) async throws -> SnapshotComparison {
        let oldByPath = Dictionary(uniqueKeysWithValues: older.map { ($0.relativePath, $0) })
        let newByPath = Dictionary(uniqueKeysWithValues: newer.map { ($0.relativePath, $0) })
        let oldFolderSizes = folderLogicalSizes(from: older)
        let newFolderSizes = folderLogicalSizes(from: newer)
        let allPaths = Set(oldByPath.keys).union(newByPath.keys).sorted()
        let comparisonStarted = Date()
        var changes: [FileChange] = []
        changes.reserveCapacity(allPaths.count)

        for (index, path) in allPaths.enumerated() {
            try Task.checkCancellation()
            let old = oldByPath[path]
            let new = newByPath[path]
            let kind: ChangeKind
            switch (old, new) {
            case (nil, .some): kind = .added
            case (.some, nil): kind = .removed
            case let (.some(previous), .some(current)):
                if previous.itemType != current.itemType {
                    kind = .typeChanged
                } else if contentChanged(previous, current) {
                    kind = .modified
                } else if metadataChanged(previous, current) {
                    kind = .metadataChanged
                } else {
                    kind = .unchanged
                }
            case (nil, nil): continue
            }
            if kind != .unchanged {
                changes.append(FileChange(
                    id: UUID(),
                    relativePath: path,
                    kind: kind,
                    oldMetadata: old,
                    newMetadata: new,
                    oldLogicalSize: old?.isDirectory == true ? oldFolderSizes[path] ?? 0 : nil,
                    newLogicalSize: new?.isDirectory == true ? newFolderSizes[path] ?? 0 : nil
                ))
            }

            if index == allPaths.count - 1 || index.isMultiple(of: 1024) {
                let elapsedTime = max(Date().timeIntervalSince(comparisonStarted), 0.001)
                await progress(ScanProgress(
                    phase: "Comparing changes",
                    rootName: "Both snapshots",
                    itemsScanned: index + 1,
                    estimatedItemCount: allPaths.count,
                    elapsedTime: elapsedTime,
                    itemsPerSecond: Double(index + 1) / elapsedTime,
                    startedAt: nil
                ))
                await Task.yield()
            }
        }

        let directChangedPaths = Set(changes.map(\.relativePath))
        let folders = Set(older.filter(\.isDirectory).map(\.relativePath)).union(newer.filter(\.isDirectory).map(\.relativePath))
        var changedFolderPaths = Set<String>()
        for change in changes {
            let components = change.relativePath.split(separator: "/")
            guard components.count > 1 else { continue }
            for index in 0..<(components.count - 1) {
                changedFolderPaths.insert(components[0...index].joined(separator: "/"))
            }
        }
        for folder in folders where !directChangedPaths.contains(folder) {
            if changedFolderPaths.contains(folder) {
                let old = oldByPath[folder]
                let new = newByPath[folder]
                changes.append(FileChange(
                    id: UUID(),
                    relativePath: folder,
                    kind: .folderContentsChanged,
                    oldMetadata: old,
                    newMetadata: new,
                    oldLogicalSize: oldFolderSizes[folder] ?? 0,
                    newLogicalSize: newFolderSizes[folder] ?? 0
                ))
            }
        }

        try Task.checkCancellation()
        let elapsedTime = max(Date().timeIntervalSince(comparisonStarted), 0.001)
        await progress(ScanProgress(
            phase: "Preparing results",
            rootName: "Both snapshots",
            itemsScanned: allPaths.count,
            estimatedItemCount: allPaths.count,
            elapsedTime: elapsedTime,
            itemsPerSecond: Double(allPaths.count) / elapsedTime,
            startedAt: nil
        ))

        let added = changes.filter { $0.kind == .added && !$0.isFolder }
        let removed = changes.filter { $0.kind == .removed && !$0.isFolder }
        let changed = changes.filter { [.modified, .typeChanged, .metadataChanged].contains($0.kind) && !$0.isFolder }
        let contentChanged = changed.filter { [.modified, .typeChanged].contains($0.kind) }
        let summary = ComparisonSummary(
            addedCount: added.count,
            removedCount: removed.count,
            modifiedCount: changed.count,
            folderChangeCount: changes.filter { $0.isFolder }.count,
            logicalBytesAdded: uniqueByteTotal(added, metadata: { $0.newMetadata }),
            logicalBytesRemoved: uniqueByteTotal(removed, metadata: { $0.oldMetadata }),
            logicalBytesModified: uniqueByteTotal(contentChanged, metadata: { $0.newMetadata ?? $0.oldMetadata }),
            duration: duration
        )
        let folderImpacts = Set(oldFolderSizes.keys)
            .union(newFolderSizes.keys)
            .compactMap { path -> FolderImpact? in
                let oldSize = oldFolderSizes[path] ?? 0
                let newSize = newFolderSizes[path] ?? 0
                guard oldSize != newSize else { return nil }
                return FolderImpact(
                    relativePath: path,
                    oldLogicalSize: oldSize,
                    newLogicalSize: newSize
                )
            }
        return SnapshotComparison(
            olderSnapshot: olderSnapshot,
            newerSnapshot: newerSnapshot,
            changes: changes,
            folderImpacts: folderImpacts,
            summary: summary,
            warnings: []
        )
    }

    private func contentChanged(_ old: FileMetadata, _ new: FileMetadata) -> Bool {
        guard old.itemType == .file else { return old.symbolicLinkDestination != new.symbolicLinkDestination }
        if old.size != new.size { return true }
        if old.modificationDate != new.modificationDate { return true }
        return old.checksum != nil && new.checksum != nil && old.checksum != new.checksum
    }

    private func metadataChanged(_ old: FileMetadata, _ new: FileMetadata) -> Bool {
        old.creationDate != new.creationDate || old.permissions != new.permissions || old.symbolicLinkDestination != new.symbolicLinkDestination || old.isPackage != new.isPackage
    }

    private func folderLogicalSizes(from records: [FileMetadata]) -> [String: UInt64] {
        var sizes: [String: UInt64] = [:]
        var identifiersByFolder: [String: Set<UInt64>] = [:]

        for record in records where !record.isDirectory {
            let components = record.relativePath.split(separator: "/")
            guard components.count > 1 else { continue }

            for index in 0..<(components.count - 1) {
                let folder = components[0...index].joined(separator: "/")
                if let identifier = record.fileIdentifier {
                    var identifiers = identifiersByFolder[folder, default: []]
                    guard identifiers.insert(identifier).inserted else { continue }
                    identifiersByFolder[folder] = identifiers
                }
                sizes[folder, default: 0] += record.size
            }
        }

        return sizes
    }

    private func uniqueByteTotal(_ changes: [FileChange], metadata: (FileChange) -> FileMetadata?) -> UInt64 {
        var countedIdentifiers = Set<UInt64>()
        return changes.reduce(0) { total, change in
            guard let record = metadata(change) else { return total }
            if let identifier = record.fileIdentifier {
                guard countedIdentifiers.insert(identifier).inserted else { return total }
            }
            return total + record.size
        }
    }
}
