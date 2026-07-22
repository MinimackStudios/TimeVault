import Foundation

struct PreferencesStore: Sendable {
    private let olderKey = "recentOlderSnapshot"
    private let newerKey = "recentNewerSnapshot"

    func save(older: BackupSnapshot?, newer: BackupSnapshot?) {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(older), forKey: olderKey)
        defaults.set(try? JSONEncoder().encode(newer), forKey: newerKey)
    }

    func loadOlder() -> BackupSnapshot? { decode(key: olderKey) }
    func loadNewer() -> BackupSnapshot? { decode(key: newerKey) }

    private func decode<T: Decodable>(key: String) -> T? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
