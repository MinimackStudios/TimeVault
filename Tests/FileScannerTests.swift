import Foundation
import XCTest
@testable import TimeMachineAnalyzer

final class FileScannerTests: XCTestCase {
    func testCancellationIsReported() async throws {
        let scanner = FileScanner(fileSystem: SlowFileSystem())
        let task = Task {
            do {
                for try await _ in scanner.events(for: URL(fileURLWithPath: "/fixture"), label: "Fixture") { }
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertEqual((error as? AppError)?.errorDescription, AppError.comparisonCancelled.errorDescription)
            }
        }
        task.cancel()
        await task.value
    }
}

private struct SlowFileSystem: FileSystem {
    func scan(root: URL, progress: @escaping @Sendable (Int) -> Void) throws -> [FileMetadata] {
        try Task.checkCancellation()
        progress(1)
        return []
    }
}
