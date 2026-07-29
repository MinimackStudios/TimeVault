import Foundation

struct FileScanner: Sendable {
    enum Event: Sendable {
        case progress(ScanProgress)
        case finished(FileScanResult)
    }

    let fileSystem: any FileSystem

    func events(for root: URL, label: String) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    let startedAt = Date()
                    let result = try fileSystem.scan(root: root) { count in
                        let elapsedTime = max(Date().timeIntervalSince(startedAt), 0.001)
                        continuation.yield(.progress(.init(
                            phase: "Scanning",
                            rootName: label,
                            itemsScanned: count,
                            estimatedItemCount: nil,
                            elapsedTime: elapsedTime,
                            itemsPerSecond: Double(count) / elapsedTime,
                            startedAt: startedAt
                        )))
                    }
                    try Task.checkCancellation()
                    continuation.yield(.finished(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AppError.comparisonCancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }
}
