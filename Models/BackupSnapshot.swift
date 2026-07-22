import Foundation

struct BackupSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let backupVolume: String
    let machineName: String?
    let url: URL
    let identifier: String

    init(id: UUID = UUID(), date: Date, backupVolume: String, machineName: String? = nil, url: URL, identifier: String? = nil) {
        self.id = id
        self.date = date
        self.backupVolume = backupVolume
        self.machineName = machineName
        self.url = url
        self.identifier = identifier ?? url.path
    }
}
