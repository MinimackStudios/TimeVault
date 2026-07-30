import Foundation

protocol PermissionChecking: Sendable {
    func verifyReadAccess(to url: URL) -> PermissionState
}

enum PermissionState: Sendable {
    case unknown
    case verified
    case inaccessible(String)
}

struct PermissionService: PermissionChecking, Sendable {
    static let recoveryInstructions = "The selected location is not readable. Use Choose Volume to approve it, or enable Full Disk Access in System Settings > Privacy & Security if macOS still blocks access."

    static var fullDiskAccessSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    func verifyReadAccess(to url: URL) -> PermissionState {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .inaccessible(Self.recoveryInstructions)
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            return .verified
        } catch {
            return .inaccessible("\(Self.recoveryInstructions) Technical detail: \(error.localizedDescription)")
        }
    }
}
