import Foundation

enum FileItemType: String, Codable, CaseIterable, Sendable {
    case file
    case directory
    case symbolicLink
    case other
}

struct FileMetadata: Codable, Hashable, Sendable {
    let relativePath: String
    let itemType: FileItemType
    let size: UInt64
    let modificationDate: Date?
    let creationDate: Date?
    let permissions: UInt16?
    let fileIdentifier: UInt64?
    let symbolicLinkDestination: String?
    let isPackage: Bool
    let checksum: String?

    var isDirectory: Bool { itemType == .directory }
    var fileName: String { URL(fileURLWithPath: relativePath).lastPathComponent }
}
