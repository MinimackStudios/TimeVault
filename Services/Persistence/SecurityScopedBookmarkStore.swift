import Foundation

struct SecurityScopedBookmarkStore: Sendable {
    private let key = "approvedBackupVolumeBookmarks"

    func save(url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        var values = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        values[url.path] = data
        UserDefaults.standard.set(values, forKey: key)
    }

    func restore() -> [URL] {
        let values = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        return values.compactMap { path, data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale), !stale else { return nil }
            return url
        }
    }
}
