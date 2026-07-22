import Foundation

enum PermissionState: Sendable {
    case unknown
    case verified
    case inaccessible(String)
}

struct PermissionService: Sendable {
    func verifyReadAccess(to url: URL) -> PermissionState {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .inaccessible("The selected location is not readable. Approve it in the open panel, or enable Full Disk Access in System Settings > Privacy & Security if macOS still blocks access.")
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            return .verified
        } catch {
            return .inaccessible(error.localizedDescription)
        }
    }
}
