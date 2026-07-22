import Foundation

enum ChangeKind: String, Codable, CaseIterable, Sendable {
    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
    case unchanged = "Unchanged"
    case typeChanged = "Type changed"
    case metadataChanged = "Metadata changed"
    case folderContentsChanged = "Folder contents changed"

    var systemImage: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .unchanged: return "checkmark.circle"
        case .typeChanged: return "arrow.triangle.2.circlepath.circle.fill"
        case .metadataChanged: return "tag.circle.fill"
        case .folderContentsChanged: return "folder.badge.gearshape"
        }
    }
}

struct FileChange: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let relativePath: String
    let kind: ChangeKind
    let oldMetadata: FileMetadata?
    let newMetadata: FileMetadata?
    let oldLogicalSize: UInt64?
    let newLogicalSize: UInt64?

    var oldSize: UInt64? { isFolder ? oldLogicalSize : oldMetadata?.size }
    var newSize: UInt64? { isFolder ? newLogicalSize : newMetadata?.size }
    var sizeDifference: Int64 {
        Int64(newSize ?? 0) - Int64(oldSize ?? 0)
    }
    var isFolder: Bool {
        oldMetadata?.isDirectory == true || newMetadata?.isDirectory == true
    }
    var fileName: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    var oldSizeForSorting: UInt64 { oldSize ?? 0 }
    var newSizeForSorting: UInt64 { newSize ?? 0 }
    var oldModificationDateForSorting: Date { oldMetadata?.modificationDate ?? .distantPast }
    var newModificationDateForSorting: Date { newMetadata?.modificationDate ?? .distantPast }
}
