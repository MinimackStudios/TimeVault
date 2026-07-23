import AppKit
import Foundation
import OSLog
import SwiftUI

enum AppSection: Hashable {
    case welcome
    case snapshots
    case comparison
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var section: AppSection = .welcome
    @Published var mountedVolumes: [URL] = []
    @Published var selectedVolume: URL?
    @Published var snapshots: [BackupSnapshot] = []
    @Published var olderSnapshot: BackupSnapshot?
    @Published var newerSnapshot: BackupSnapshot?
    @Published var comparison: SnapshotComparison? { didSet { invalidateFilteredChangesCache() } }
    @Published var selectedChangeID: UUID?
    @Published var searchText = "" { didSet { invalidateFilteredChangesCache() } }
    @Published var filter: ChangeFilter = .all { didSet { invalidateFilteredChangesCache() } }
    @Published var sortOrder: [KeyPathComparator<FileChange>] = [KeyPathComparator(\.relativePath)] { didSet { invalidateFilteredChangesCache() } }
    @Published var isDiscovering = false
    @Published var isComparing = false
    @Published var progress: ScanProgress?
    @Published var permissionState: PermissionState = .unknown
    @Published var errorMessage: String?
    @Published var diagnostics: String?

    private let discovery = TimeMachineSnapshotDiscovery()
    private let permissions = PermissionService()
    private let bookmarks = SecurityScopedBookmarkStore()
    private let exportService = ExportService()
    private let logger = Logger(subsystem: "com.minimackstudios.TimeVault", category: "workflow")
    private var comparisonTask: Task<Void, Never>?
    private var activeSecurityScopedURL: URL?
    private var filteredChangesCache: [FileChange] = []
    private var filteredChangesCacheIsValid = false

    init() {
        mountedVolumes = bookmarks.restore()
        refreshMountedVolumes()
    }

    deinit {
        comparisonTask?.cancel()
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    var filteredChanges: [FileChange] {
        if filteredChangesCacheIsValid { return filteredChangesCache }
        guard let changes = comparison?.changes else {
            filteredChangesCache = []
            filteredChangesCacheIsValid = true
            return filteredChangesCache
        }
        let filtered = changes.filter { change in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .added: matchesFilter = change.kind == .added
            case .removed: matchesFilter = change.kind == .removed
            case .modified: matchesFilter = [.modified, .typeChanged, .metadataChanged, .folderContentsChanged].contains(change.kind)
            case .folders: matchesFilter = change.isFolder
            case .files: matchesFilter = !change.isFolder
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return matchesFilter && (query.isEmpty || change.relativePath.localizedCaseInsensitiveContains(query))
        }
        var sorted = filtered
        sorted.sort(using: sortOrder)
        filteredChangesCache = sorted
        filteredChangesCacheIsValid = true
        return filteredChangesCache
    }

    private func invalidateFilteredChangesCache() {
        filteredChangesCacheIsValid = false
    }

    func refreshMountedVolumes() {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey], options: [.skipHiddenVolumes]) ?? []
        let candidates = Array(Set(mountedVolumes + urls)).filter { volume in
            discovery.validate(volume: volume).isCandidate
        }
        mountedVolumes = candidates.sorted { $0.path < $1.path }
    }

    func chooseBackupVolume() {
        let panel = NSOpenPanel()
        panel.title = "Choose Time Machine Backup Volume"
        panel.message = "Choose a mounted, read-only Time Machine backup volume."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectVolume(url)
        guard case .verified = permissionState else { return }
        try? bookmarks.save(url: url)
        section = .snapshots
        discoverSnapshots()
    }

    func chooseFolderSnapshot(isOlder: Bool) {
        let panel = NSOpenPanel()
        panel.title = isOlder ? "Choose Older Snapshot Folder" : "Choose Newer Snapshot Folder"
        panel.message = "Choose a folder representing a snapshot. Access is read-only."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let date = values?.contentModificationDate ?? Date()
        let normalizedURL = url.standardizedFileURL
        let snapshot = snapshots.first(where: { $0.url.standardizedFileURL == normalizedURL }) ?? BackupSnapshot(
            date: date,
            backupVolume: url.deletingLastPathComponent().lastPathComponent,
            machineName: "Custom folder",
            url: normalizedURL,
            identifier: normalizedURL.path
        )
        if !snapshots.contains(where: { $0.url.standardizedFileURL == normalizedURL }) {
            snapshots.append(snapshot)
        }
        if isOlder { olderSnapshot = snapshot } else { newerSnapshot = snapshot }
        section = .snapshots
    }

    func discoverSnapshots() {
        guard let selectedVolume else { return }
        isDiscovering = true
        errorMessage = nil
        diagnostics = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let validation = self.discovery.validate(volume: selectedVolume)
                guard validation.isCandidate else { throw AppError.notTimeMachineVolume(validation.detail) }
                let found = try await self.discovery.discover(on: selectedVolume)
                self.snapshots = found
            } catch {
                self.present(error)
            }
            self.isDiscovering = false
        }
    }

    func selectVolume(_ url: URL) {
        if activeSecurityScopedURL != url {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
            if url.startAccessingSecurityScopedResource() { activeSecurityScopedURL = url }
        }
        selectedVolume = url
        refreshMountedVolumes()
        snapshots = []
        olderSnapshot = nil
        newerSnapshot = nil
        comparison = nil
        permissionState = permissions.verifyReadAccess(to: url)
    }

    func compareSnapshots() {
        guard let olderSnapshot, let newerSnapshot else {
            errorMessage = "Choose both an older and a newer snapshot first."
            return
        }
        comparisonTask?.cancel()
        isComparing = true
        comparison = nil
        errorMessage = nil
        progress = ScanProgress(phase: "Preparing", rootName: "Snapshots", itemsScanned: 0, estimatedItemCount: nil, elapsedTime: 0, itemsPerSecond: 0, startedAt: Date())
        let service = ComparisonService(scanner: FileScanner(fileSystem: LocalFileSystem()), engine: ComparisonEngine())
        comparisonTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.compare(olderSnapshot: olderSnapshot, newerSnapshot: newerSnapshot) { progress in
                    await MainActor.run { self.progress = progress }
                }
                await MainActor.run {
                    self.comparison = result
                    self.section = .comparison
                    self.logger.info("Comparison completed with \(result.changes.count) changed paths")
                    self.isComparing = false
                }
            } catch {
                await MainActor.run {
                    if case AppError.comparisonCancelled = error {
                        self.errorMessage = nil
                        self.diagnostics = nil
                    } else {
                        self.present(error)
                    }
                    self.isComparing = false
                }
            }
        }
    }

    func cancelComparison() {
        comparisonTask?.cancel()
        isComparing = false
        progress = nil
        errorMessage = nil
        diagnostics = nil
    }

    func exportJSON() { export(extension: "json") { try exportService.writeJSON($0, to: $1) } }
    func exportCSV() { export(extension: "csv") { try exportService.writeCSV($0, to: $1) } }

    func selectedChange() -> FileChange? {
        guard let selectedChangeID else { return nil }
        return comparison?.changes.first { $0.id == selectedChangeID }
    }

    func revealSelectedInFinder() {
        guard let change = selectedChange() else { return }
        let base = change.newMetadata != nil ? newerSnapshot?.url : olderSnapshot?.url
        guard let base else { return }
        NSWorkspace.shared.activateFileViewerSelecting([base.appendingPathComponent(change.relativePath)])
    }

    func revealFolderImpactInFinder(_ impact: FolderImpact) {
        let base = impact.newLogicalSize > 0 ? newerSnapshot?.url : olderSnapshot?.url
        guard let base else { return }
        NSWorkspace.shared.activateFileViewerSelecting([base.appendingPathComponent(impact.relativePath)])
    }

    private func export(extension fileExtension: String, action: (SnapshotComparison, URL) throws -> Void) {
        guard let comparison else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = fileExtension == "json" ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = "snapshot-comparison.\(fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try action(comparison, url) } catch { present(error) }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostics = String(describing: error)
        logger.error("Workflow error: \(String(describing: error), privacy: .public)")
    }
}

enum ChangeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
    case folders = "Folders"
    case files = "Files"
    var id: String { rawValue }
}
