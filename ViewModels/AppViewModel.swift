import AppKit
import Foundation
import OSLog
import SwiftUI

enum AppSection: Hashable {
    case dashboard
    case snapshots(URL?)
    case comparison
}

@MainActor
final class AppViewModel: ObservableObject {
    enum SnapshotRole {
        case older
        case newer
    }

    typealias ComparisonOperation = @Sendable (
        BackupSnapshot,
        BackupSnapshot,
        @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> SnapshotComparison

    @Published var section: AppSection = .dashboard
    @Published var mountedVolumes: [URL] = []
    @Published var selectedVolume: URL?
    @Published var snapshots: [BackupSnapshot] = []
    @Published private(set) var olderSnapshot: BackupSnapshot?
    @Published private(set) var newerSnapshot: BackupSnapshot?
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
    @Published var systemOverview: SystemOverview?
    @Published var localSnapshots: [LocalSnapshot] = []
    @Published var localSnapshotStatus: LocalSnapshotDiscoveryStatus = .unavailable
    @Published var isRefreshingSystemOverview = false

    private let discovery: TimeMachineSnapshotDiscovery
    private let permissions: any PermissionChecking
    private let bookmarks: SecurityScopedBookmarkStore
    private let exportService = ExportService()
    private let systemStatus = SystemStatusService()
    private let comparisonOperation: ComparisonOperation
    private let logger = Logger(subsystem: "com.minimackstudios.TimeVault", category: "workflow")
    private var comparisonTask: Task<Void, Never>?
    private var activeComparisonID: UUID?
    private var activeSecurityScopedURLs: [String: URL] = [:]
    private var approvedVolumeURLs: [URL] = []
    private var configuredDestinationPaths: Set<String> = []
    private var permissionRecoveryURL: URL?
    private var accessRevalidationTask: Task<Void, Never>?
    private var destinationRefreshTask: Task<Void, Never>?
    private var filteredChangesCache: [FileChange] = []
    private var filteredChangesCacheIsValid = false

    init(
        comparisonOperation: @escaping ComparisonOperation = { olderSnapshot, newerSnapshot, progress in
            try await AppViewModel.performComparison(
                olderSnapshot: olderSnapshot,
                newerSnapshot: newerSnapshot,
                progress: progress
            )
        },
        performInitialRefresh: Bool = true,
        permissionService: any PermissionChecking = PermissionService(),
        bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore(),
        snapshotDiscovery: TimeMachineSnapshotDiscovery = TimeMachineSnapshotDiscovery()
    ) {
        self.comparisonOperation = comparisonOperation
        self.permissions = permissionService
        self.bookmarks = bookmarkStore
        self.discovery = snapshotDiscovery
        if performInitialRefresh {
            approvedVolumeURLs = restoreApprovedVolumes()
            mountedVolumes = approvedVolumeURLs
            refreshMountedVolumes()
            refreshSystemOverview()
            scheduleApprovedVolumeRevalidation()
        }
    }

    deinit {
        comparisonTask?.cancel()
        accessRevalidationTask?.cancel()
        destinationRefreshTask?.cancel()
        activeSecurityScopedURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    var isWorkflowBusy: Bool {
        isDiscovering || isComparing
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

    var shouldShowPermissionRecovery: Bool {
        if case .inaccessible = permissionState { return true }
        return false
    }

    private func invalidateFilteredChangesCache() {
        filteredChangesCacheIsValid = false
    }

    private func snapshotsMatch(_ left: BackupSnapshot?, _ right: BackupSnapshot?) -> Bool {
        guard let left, let right else { return false }
        return left.id == right.id || left.url.standardizedFileURL == right.url.standardizedFileURL
    }

    func refreshMountedVolumes() {
        updateMountedVolumes()

        destinationRefreshTask?.cancel()
        let discovery = self.discovery
        destinationRefreshTask = Task { [weak self] in
            guard let destinationPaths = await discovery.configuredDestinationPaths(),
                  !Task.isCancelled,
                  let self else { return }
            self.configuredDestinationPaths = destinationPaths
            self.updateMountedVolumes()
        }
    }

    private func updateMountedVolumes() {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey], options: [.skipHiddenVolumes]) ?? []
        let mountedPaths = Set(urls.map { $0.standardizedFileURL.path })
        let approvedPaths = Set(approvedVolumeURLs.map { $0.standardizedFileURL.path })
        let candidates = Array(Set(approvedVolumeURLs + mountedVolumes + urls)).filter { volume in
            let path = volume.standardizedFileURL.path
            guard mountedPaths.contains(path) else { return false }
            return approvedPaths.contains(path)
                || configuredDestinationPaths.contains(path)
                || discovery.isSidebarCandidate(volume: volume)
        }
        mountedVolumes = candidates.sorted { $0.path < $1.path }
    }

    func refreshSystemOverview() {
        guard !isRefreshingSystemOverview else { return }
        isRefreshingSystemOverview = true
        Task { [weak self] in
            guard let self else { return }
            let dashboard = await self.systemStatus.loadDashboard()
            self.systemOverview = dashboard.overview
            self.localSnapshots = dashboard.localSnapshots
            self.localSnapshotStatus = dashboard.overview.localSnapshotStatus
            self.isRefreshingSystemOverview = false
        }
    }

    func navigate(to destination: AppSection) {
        guard !isDiscovering else { return }
        switch destination {
        case .snapshots(let volume):
            section = destination
            guard let volume else { return }
            if selectedVolume != volume {
                selectVolume(volume)
                discoverSnapshots()
            } else if snapshots.isEmpty, !isDiscovering {
                discoverSnapshots()
            }
        case .dashboard, .comparison:
            section = destination
        }
    }

    func showSnapshotBrowser() {
        guard !isWorkflowBusy else { return }
        navigate(to: .snapshots(selectedVolume ?? mountedVolumes.first))
    }

    func chooseBackupVolume() {
        guard !isWorkflowBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Time Machine Backup Volume"
        panel.message = "Choose a mounted, read-only Time Machine backup volume."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectVolume(url)
        guard case .verified = permissionState else { return }
        rememberApprovedVolume(url)
        section = .snapshots(url)
        discoverSnapshots()
    }

    func openFullDiskAccessSettings() {
        guard !isWorkflowBusy else { return }
        guard let url = PermissionService.fullDiskAccessSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func recheckSelectedVolumeAccess() {
        guard !isWorkflowBusy else { return }
        revalidateStoredVolumeAccess()
        guard let accessTarget = permissionRecoveryURL ?? selectedVolume else { return }
        guard verifyReadAccess(to: accessTarget) else { return }
        rememberSelectedVolumeIfApproved()
        discoverSnapshots()
    }

    func revalidateSelectedVolumeAccess() {
        revalidateStoredVolumeAccess()
        refreshMountedVolumes()
        defer { scheduleApprovedVolumeRevalidation() }
        guard let selectedVolume else { return }
        let accessTarget = permissionRecoveryURL ?? selectedVolume
        let wasInaccessible = shouldShowPermissionRecovery
        guard verifyReadAccess(to: accessTarget) else { return }
        rememberSelectedVolumeIfApproved()
        if (wasInaccessible || snapshots.isEmpty) && !isDiscovering {
            discoverSnapshots()
        }
    }

    func chooseFolderSnapshot(isOlder: Bool) {
        guard !isWorkflowBusy else { return }
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
        selectSnapshot(snapshot, as: isOlder ? .older : .newer)
        section = .snapshots(selectedVolume)
    }

    func selectSnapshot(_ snapshot: BackupSnapshot?, as role: SnapshotRole) {
        guard !isDiscovering else { return }
        switch role {
        case .older:
            olderSnapshot = snapshot
            if snapshotsMatch(snapshot, newerSnapshot) {
                newerSnapshot = nil
            }
        case .newer:
            newerSnapshot = snapshot
            if snapshotsMatch(snapshot, olderSnapshot) {
                olderSnapshot = nil
            }
        }
    }

    func discoverSnapshots() {
        guard let selectedVolume, !isWorkflowBusy else { return }
        isDiscovering = true
        errorMessage = nil
        diagnostics = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let validation = self.discovery.validate(volume: selectedVolume)
                guard validation.isCandidate else { throw AppError.notTimeMachineVolume(validation.detail) }
                let found = try await self.discovery.discover(on: selectedVolume)
                self.reconcileSnapshots(with: found)
            } catch {
                self.present(error)
            }
            self.isDiscovering = false
        }
    }

    func selectVolume(_ url: URL) {
        guard !isWorkflowBusy else { return }
        beginSecurityScopedAccess(for: url)
        selectedVolume = url
        refreshMountedVolumes()
        snapshots = []
        olderSnapshot = nil
        newerSnapshot = nil
        comparison = nil
        permissionState = permissions.verifyReadAccess(to: url)
        permissionRecoveryURL = {
            if case .inaccessible = permissionState { return url }
            return nil
        }()
        if discovery.validate(volume: url).isCandidate {
            rememberApprovedVolume(url)
        }
    }

    func compareSnapshots() {
        guard !isDiscovering else { return }
        guard let olderSnapshot, let newerSnapshot else {
            errorMessage = "Choose both an older and a newer snapshot first."
            return
        }
        comparisonTask?.cancel()
        let comparisonID = UUID()
        activeComparisonID = comparisonID
        isComparing = true
        comparison = nil
        errorMessage = nil
        progress = ScanProgress(phase: "Preparing", rootName: "Snapshots", itemsScanned: 0, estimatedItemCount: nil, elapsedTime: 0, itemsPerSecond: 0, startedAt: Date())
        let operation = comparisonOperation
        comparisonTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await operation(olderSnapshot, newerSnapshot) { progress in
                    await MainActor.run {
                        guard self.activeComparisonID == comparisonID else { return }
                        self.progress = progress
                    }
                }
                await MainActor.run {
                    guard self.activeComparisonID == comparisonID else { return }
                    self.comparison = result
                    self.section = .comparison
                    self.logger.info("Comparison completed with \(result.changes.count) changed paths")
                    self.isComparing = false
                    self.progress = nil
                    self.comparisonTask = nil
                    self.activeComparisonID = nil
                }
            } catch {
                await MainActor.run {
                    guard self.activeComparisonID == comparisonID else { return }
                    if case AppError.comparisonCancelled = error {
                        self.errorMessage = nil
                        self.diagnostics = nil
                    } else {
                        self.present(error)
                    }
                    self.isComparing = false
                    self.progress = nil
                    self.comparisonTask = nil
                    self.activeComparisonID = nil
                }
            }
        }
    }

    func cancelComparison() {
        activeComparisonID = nil
        comparisonTask?.cancel()
        comparisonTask = nil
        isComparing = false
        progress = nil
        errorMessage = nil
        diagnostics = nil
    }

    nonisolated private static func performComparison(
        olderSnapshot: BackupSnapshot,
        newerSnapshot: BackupSnapshot,
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> SnapshotComparison {
        let service = ComparisonService(
            scanner: FileScanner(fileSystem: LocalFileSystem()),
            engine: ComparisonEngine()
        )
        return try await service.compare(
            olderSnapshot: olderSnapshot,
            newerSnapshot: newerSnapshot,
            progress: progress
        )
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
        logger.error("Workflow error: \(String(describing: error), privacy: .private)")
        if case AppError.permissionDenied(let url) = error {
            permissionRecoveryURL = url
            permissionState = .inaccessible(PermissionService.recoveryInstructions)
            errorMessage = nil
            diagnostics = nil
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostics = String(describing: error)
    }

    private func restoreApprovedVolumes() -> [URL] {
        var restoredURLs: [URL] = []
        for bookmark in bookmarks.restoreEntries() {
            let normalizedURL = bookmark.url.standardizedFileURL
            if !restoredURLs.contains(normalizedURL) {
                restoredURLs.append(normalizedURL)
            }
            beginSecurityScopedAccess(for: bookmark.scopedURL)
        }
        return restoredURLs.sorted { $0.path < $1.path }
    }

    private func revalidateStoredVolumeAccess() {
        for url in approvedVolumeURLs {
            beginSecurityScopedAccess(for: url)
        }

        for bookmark in bookmarks.restoreEntries() {
            let normalizedURL = bookmark.url.standardizedFileURL
            if !approvedVolumeURLs.contains(normalizedURL) {
                approvedVolumeURLs.append(normalizedURL)
            }
            beginSecurityScopedAccess(for: bookmark.scopedURL)
        }
    }

    private func rememberApprovedVolume(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        if !approvedVolumeURLs.contains(normalizedURL) {
            approvedVolumeURLs.append(normalizedURL)
        }
        try? bookmarks.save(url: url)
        updateMountedVolumes()
    }

    private func rememberSelectedVolumeIfApproved() {
        guard let selectedVolume,
              discovery.validate(volume: selectedVolume).isCandidate else { return }
        rememberApprovedVolume(selectedVolume)
    }

    @discardableResult
    private func beginSecurityScopedAccess(for url: URL) -> Bool {
        let normalizedURL = url.standardizedFileURL
        let key = normalizedURL.path
        guard activeSecurityScopedURLs[key] == nil else { return true }
        guard url.startAccessingSecurityScopedResource() else { return false }
        activeSecurityScopedURLs[key] = url
        return true
    }

    private func scheduleApprovedVolumeRevalidation() {
        accessRevalidationTask?.cancel()
        accessRevalidationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.revalidateStoredVolumeAccess()
            self.refreshMountedVolumes()
        }
    }

    @discardableResult
    private func verifyReadAccess(to url: URL) -> Bool {
        if let selectedVolume {
            beginSecurityScopedAccess(for: selectedVolume)
        }
        beginSecurityScopedAccess(for: url)
        permissionState = permissions.verifyReadAccess(to: url)
        errorMessage = nil
        diagnostics = nil
        if case .inaccessible = permissionState {
            permissionRecoveryURL = url
            return false
        }
        permissionRecoveryURL = nil
        return true
    }

    private func reconcileSnapshots(with discoveredSnapshots: [BackupSnapshot]) {
        var reconciledSnapshots = discoveredSnapshots

        func resolve(_ selection: BackupSnapshot?) -> BackupSnapshot? {
            guard let selection else { return nil }
            if let refreshedSnapshot = reconciledSnapshots.first(where: { snapshotsMatch($0, selection) }) {
                return refreshedSnapshot
            }
            if !reconciledSnapshots.contains(where: { snapshotsMatch($0, selection) }) {
                reconciledSnapshots.append(selection)
            }
            return selection
        }

        let reconciledOlderSnapshot = resolve(olderSnapshot)
        let reconciledNewerSnapshot = resolve(newerSnapshot)
        snapshots = reconciledSnapshots
        olderSnapshot = reconciledOlderSnapshot
        newerSnapshot = reconciledNewerSnapshot
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
