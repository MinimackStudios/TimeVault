import Foundation

protocol FileSystem: Sendable {
    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> [FileMetadata]
}

struct LocalFileSystem: FileSystem {
    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> [FileMetadata] {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: root.path) else {
            throw AppError.permissionDenied(root)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .fileResourceIdentifierKey, .isPackageKey, .volumeIsReadOnlyKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw AppError.snapshotUnavailable(root)
        }

        var records: [FileMetadata] = []
        var count = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
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
                records.append(FileMetadata(
                    relativePath: relativePath,
                    itemType: type,
                    size: UInt64(max(0, values.fileSize ?? 0)),
                    modificationDate: values.contentModificationDate,
                    creationDate: values.creationDate,
                    permissions: try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? UInt16,
                    fileIdentifier: identifier,
                    symbolicLinkDestination: destination,
                    isPackage: values.isPackage ?? false,
                    checksum: nil
                ))
                count += 1
                if count % 256 == 0 { progress(count) }
            } catch {
                continue
            }
        }
        progress(count)
        return records
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
