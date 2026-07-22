import Foundation
import XCTest
@testable import TimeMachineAnalyzer

final class ComparisonEngineTests: XCTestCase {
    func testAddedRemovedModifiedAndMetadataChanges() async throws {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let old = [
            metadata("removed.txt", size: 4, date: oldDate),
            metadata("changed.txt", size: 3, date: oldDate),
            metadata("permissions.txt", size: 3, date: oldDate, permissions: 0o644),
            metadata("folder", type: .directory)
        ]
        let new = [
            metadata("added.txt", size: 7, date: newDate),
            metadata("changed.txt", size: 5, date: newDate),
            metadata("permissions.txt", size: 3, date: oldDate, permissions: 0o600),
            metadata("folder", type: .directory)
        ]
        let comparison = try await ComparisonEngine().compare(older: old, newer: new, olderSnapshot: snapshot("old"), newerSnapshot: snapshot("new"), duration: 1, progress: { _ in })
        XCTAssertEqual(comparison.changes.first(where: { $0.relativePath == "added.txt" })?.kind, .added)
        XCTAssertEqual(comparison.changes.first(where: { $0.relativePath == "removed.txt" })?.kind, .removed)
        XCTAssertEqual(comparison.changes.first(where: { $0.relativePath == "changed.txt" })?.kind, .modified)
        XCTAssertEqual(comparison.changes.first(where: { $0.relativePath == "permissions.txt" })?.kind, .metadataChanged)
        XCTAssertEqual(comparison.summary.logicalBytesAdded, 7)
        XCTAssertEqual(comparison.summary.logicalBytesRemoved, 4)
        XCTAssertEqual(comparison.summary.logicalBytesModified, 5)
    }

    func testTypeChangesAndFolderContentChanges() async throws {
        let old = [metadata("item", size: 0, type: .file), metadata("folder", type: .directory)]
        let new = [metadata("item", size: 0, type: .directory), metadata("folder", type: .directory), metadata("folder/new.txt", size: 2)]
        let comparison = try await ComparisonEngine().compare(older: old, newer: new, olderSnapshot: snapshot("old"), newerSnapshot: snapshot("new"), duration: 0, progress: { _ in })
        XCTAssertEqual(comparison.changes.first(where: { $0.relativePath == "item" })?.kind, .typeChanged)
        XCTAssertEqual(comparison.changes.first(where: { $0.relativePath == "folder" })?.kind, .folderContentsChanged)
    }

    func testPathNormalization() {
        XCTAssertEqual(PathNormalizer.normalize("./Documents/../Documents/file.txt"), "Documents/file.txt")
        XCTAssertEqual(PathNormalizer.normalize("a//b/./c"), "a/b/c")
    }

    func testSymbolicLinksAreRecordedWithoutFollowingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("target".utf8).write(to: root.appendingPathComponent("target.txt"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link.txt").path, withDestinationPath: "target.txt")
        let records = try LocalFileSystem().scan(root: root, progress: { _ in })
        XCTAssertEqual(records.first(where: { $0.relativePath == "link.txt" })?.itemType, .symbolicLink)
        XCTAssertNil(records.first(where: { $0.relativePath == "link.txt/target.txt" }))
    }

    func testHardLinkedFilesAreNotDoubleCountedInLogicalByteSummary() async throws {
        let old: [FileMetadata] = []
        let new = [
            metadata("one.txt", size: 8, fileIdentifier: 42),
            metadata("alias.txt", size: 8, fileIdentifier: 42)
        ]
        let comparison = try await ComparisonEngine().compare(older: old, newer: new, olderSnapshot: snapshot("old"), newerSnapshot: snapshot("new"), duration: 0, progress: { _ in })
        XCTAssertEqual(comparison.summary.logicalBytesAdded, 8)
        XCTAssertEqual(comparison.summary.addedCount, 2)
    }

    func testUnreadablePathProducesPermissionError() {
        let state = PermissionService().verifyReadAccess(to: URL(fileURLWithPath: "/definitely/not/a/real/backup"))
        guard case .inaccessible = state else {
            return XCTFail("Expected inaccessible permission state")
        }
    }

    func testAPFSTimeMachinePathUsesBackupSuffixTimestamp() throws {
        let path = "/Volumes/.timemachine/32094FF9-6D6D-42BA-AD5C-47F327D937C7/2026-07-21-121537.backup/2026-07-21-121537.backup"
        let component = URL(fileURLWithPath: path).lastPathComponent
        let normalized = String(component.dropLast(".backup".count))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        XCTAssertNotNil(formatter.date(from: normalized))
        XCTAssertEqual(normalized, "2026-07-21-121537")
    }

    private func metadata(_ path: String, size: UInt64 = 0, date: Date? = nil, type: FileItemType = .file, permissions: UInt16? = nil, fileIdentifier: UInt64? = nil) -> FileMetadata {
        FileMetadata(relativePath: path, itemType: type, size: size, modificationDate: date, creationDate: nil, permissions: permissions, fileIdentifier: fileIdentifier, symbolicLinkDestination: nil, isPackage: false, checksum: nil)
    }

    private func snapshot(_ name: String) -> BackupSnapshot {
        BackupSnapshot(date: Date(), backupVolume: name, url: URL(fileURLWithPath: "/tmp/\(name)"))
    }
}
