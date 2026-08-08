import Foundation

struct RestoredSecurityScopedBookmark: Sendable, Equatable {
    let url: URL
    let wasStale: Bool
}

struct SecurityScopedBookmarkStore {
    private let key = "approvedBackupVolumeBookmarks"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(url: URL) throws {
        let normalizedURL = url.standardizedFileURL
        let data = try makeBookmarkData(for: normalizedURL)
        var values = storedValues()
        values = values.filter { storedPath, _ in
            URL(fileURLWithPath: storedPath).standardizedFileURL != normalizedURL
        }
        values[storageKey(for: normalizedURL)] = data
        defaults.set(values, forKey: key)
    }

    func restore() -> [URL] {
        restoreEntries().map(\.url)
    }

    func restoreEntries() -> [RestoredSecurityScopedBookmark] {
        let values = storedValues()
        guard !values.isEmpty else { return [] }

        var migratedValues = values
        var restored: [RestoredSecurityScopedBookmark] = []
        var restoredPaths = Set<String>()

        for (storedPath, data) in values {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                continue
            }

            let normalizedURL = url.standardizedFileURL
            let normalizedPath = normalizedURL.path
            guard restoredPaths.insert(normalizedPath).inserted else { continue }
            restored.append(RestoredSecurityScopedBookmark(url: normalizedURL, wasStale: stale))

            migratedValues.removeValue(forKey: storedPath)
            if let refreshedData = stale ? try? makeBookmarkData(for: normalizedURL) : data {
                migratedValues[storageKey(for: normalizedURL)] = refreshedData
            } else {
                migratedValues[storedPath] = data
            }
        }

        if migratedValues != values {
            defaults.set(migratedValues, forKey: key)
        }

        return restored.sorted { $0.url.path < $1.url.path }
    }

    private func storedValues() -> [String: Data] {
        let rawValues = defaults.dictionary(forKey: key) ?? [:]
        return rawValues.compactMapValues { $0 as? Data }
    }

    private func storageKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func makeBookmarkData(for url: URL) throws -> Data {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
