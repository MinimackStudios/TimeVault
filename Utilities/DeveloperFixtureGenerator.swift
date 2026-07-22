import Foundation

#if DEBUG
struct DeveloperFixtureGenerator {
    struct FixturePair {
        let older: URL
        let newer: URL
    }

    static func makeKnownChangePair() throws -> FixturePair {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TimeMachineAnalyzerFixture-\(UUID().uuidString)")
        let older = root.appendingPathComponent("older")
        let newer = root.appendingPathComponent("newer")
        try FileManager.default.createDirectory(at: older.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try Data("same".utf8).write(to: older.appendingPathComponent("Documents/same.txt"))
        try Data("old".utf8).write(to: older.appendingPathComponent("Documents/changed.txt"))
        try Data("same".utf8).write(to: newer.appendingPathComponent("Documents/same.txt"))
        try Data("new content".utf8).write(to: newer.appendingPathComponent("Documents/changed.txt"))
        try Data("added".utf8).write(to: newer.appendingPathComponent("Documents/added.txt"))
        return FixturePair(older: older, newer: newer)
    }
}
#endif
