import Foundation

enum AppError: LocalizedError, Sendable {
    case notTimeMachineVolume(String)
    case noSnapshotsFound
    case permissionDenied(URL)
    case snapshotUnavailable(URL)
    case driveDisconnected(URL)
    case metadataReadFailed(URL, String)
    case tmutilFailed(String)
    case comparisonCancelled
    case invalidCache(String)

    var errorDescription: String? {
        switch self {
        case .notTimeMachineVolume(let detail): return "This volume does not appear to contain a readable Time Machine backup. \(detail)"
        case .noSnapshotsFound: return "No Time Machine snapshots were found on the selected volume."
        case .permissionDenied: return "The app cannot read this location. Grant access to the selected volume or Full Disk Access, then try again."
        case .snapshotUnavailable: return "A selected snapshot is no longer available. The backup may have been disconnected or changed."
        case .driveDisconnected: return "The backup drive appears to have been disconnected."
        case .metadataReadFailed(_, let detail): return "Some file metadata could not be read. \(detail)"
        case .tmutilFailed(let detail):
            return detail.isEmpty ? "Time Machine could not complete the requested operation." : "Time Machine could not complete the requested operation. \(detail)"
        case .comparisonCancelled: return "The comparison was cancelled."
        case .invalidCache(let detail): return "The cached metadata is unavailable or corrupt. \(detail)"
        }
    }
}
