import Foundation

protocol FileSystem: Sendable {
    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> FileScanResult
}

struct FileScanResult: Sendable {
    let records: [FileMetadata]
    let warnings: [String]
}

struct FileScanLimits: Sendable, Equatable {
    let maxItems: Int
    let maxDepth: Int
    let maxBytes: UInt64
    let maxDuration: TimeInterval

    static let `default` = FileScanLimits(
        maxItems: 250_000,
        maxDepth: 128,
        maxBytes: 1_099_511_627_776,
        maxDuration: 600
    )
}

struct LocalFileSystem: FileSystem {
    let limits: FileScanLimits

    init(limits: FileScanLimits = .default) {
        self.limits = limits
    }

    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> FileScanResult {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: root.path) else {
            throw AppError.permissionDenied(root)
        }

        let diagnostics = ScanDiagnostics(root: root)

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .fileResourceIdentifierKey, .isPackageKey, .volumeIsReadOnlyKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { url, error in
                diagnostics.record(url: url, error: error)
                return true
            }
        ) else {
            throw AppError.snapshotUnavailable(root)
        }

        var records: [FileMetadata] = []
        var count = 0
        var totalBytes: UInt64 = 0
        let scanStartedAt = Date()
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            try enforceElapsedTime(root: root, startedAt: scanStartedAt)
            guard count < limits.maxItems else {
                throw AppError.resourceLimitExceeded(root, "The scan exceeded its \(limits.maxItems)-item limit.")
            }
            guard enumerator.level <= limits.maxDepth else {
                throw AppError.resourceLimitExceeded(root, "The scan exceeded its depth limit of \(limits.maxDepth).")
            }
            let relativePath = normalizedRelativePath(url: url, root: root)
            guard !relativePath.isEmpty else { continue }

            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                let isSymlink = values.isSymbolicLink ?? false
                let type: FileItemType
                if isSymlink {
                    type = .symbolicLink
                    enumerator.skipDescendants()
                } else if values.isDirectory == true {
                    type = .directory
                } else if values.isDirectory == false {
                    type = .file
                } else {
                    type = .other
                }

                let destination = isSymlink ? try? fileManager.destinationOfSymbolicLink(atPath: url.path) : nil
                let identifier = values.fileResourceIdentifier.flatMap(Self.numericIdentifier)
                let size = UInt64(max(0, values.fileSize ?? 0))
                guard size <= limits.maxBytes - min(totalBytes, limits.maxBytes) else {
                    throw AppError.resourceLimitExceeded(root, "The scan exceeded its \(limits.maxBytes)-byte limit.")
                }
                records.append(FileMetadata(
                    relativePath: relativePath,
                    itemType: type,
                    size: size,
                    modificationDate: values.contentModificationDate,
                    creationDate: values.creationDate,
                    permissions: try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? UInt16,
                    fileIdentifier: identifier,
                    symbolicLinkDestination: destination,
                    isPackage: values.isPackage ?? false,
                    checksum: nil
                ))
                count += 1
                totalBytes += size
                if count % 256 == 0 { progress(count) }
            } catch let error as AppError {
                if case .resourceLimitExceeded = error {
                    throw error
                }
                diagnostics.record(url: url, error: error)
            } catch {
                diagnostics.record(url: url, error: error)
            }
        }
        progress(count)
        return FileScanResult(records: records, warnings: diagnostics.warnings)
    }

    private func enforceElapsedTime(root: URL, startedAt: Date) throws {
        guard Date().timeIntervalSince(startedAt) <= limits.maxDuration else {
            throw AppError.resourceLimitExceeded(root, "The scan exceeded its \(Int(limits.maxDuration))-second time limit.")
        }
    }

    private func normalizedRelativePath(url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return PathNormalizer.normalize(String(path.dropFirst(rootPath.count)))
    }

    private static func numericIdentifier(_ value: Any) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let string = value as? String { return UInt64(string) }
        return nil
    }
}

private final class ScanDiagnostics {
    private static let sampleLimit = 5

    private let root: URL
    private var skippedItemCount = 0
    private var samples: [String] = []

    init(root: URL) {
        self.root = root
    }

    func record(url: URL, error: Error) {
        skippedItemCount += 1
        guard samples.count < Self.sampleLimit else { return }

        let relativePath = relativePath(for: url)
        samples.append("\(relativePath): \(error.localizedDescription)")
    }

    var warnings: [String] {
        guard skippedItemCount > 0 else { return [] }

        let itemDescription = skippedItemCount == 1 ? "1 item" : "\(skippedItemCount) items"
        var warning = "The scan skipped \(itemDescription). Comparison results may be incomplete."
        if !samples.isEmpty {
            warning += " Examples: " + samples.joined(separator: "; ")
        }
        if skippedItemCount > samples.count {
            warning += "; plus \(skippedItemCount - samples.count) more."
        }
        return [warning]
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relativePath = PathNormalizer.normalize(String(path.dropFirst(rootPath.count)))
        return relativePath.isEmpty ? url.lastPathComponent : relativePath
    }
}
