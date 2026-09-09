import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private(set) var volumes: [VolumeInfo] = []
    private(set) var selectedVolumeOverview: VolumeInfo?
    private(set) var previousScanSummary: PreviousScanSummary?
    private(set) var previousScanRoot: FileNode?
    private(set) var isDiscoveringVolumes = true
    private(set) var result: ScanResult?
    private(set) var navigationPath: [FileNode] = []
    private(set) var isScanning = false
    private(set) var progress = ScanProgress()
    private(set) var scanningURL: URL?
    private(set) var scanStartedAt: Date?
    private(set) var pendingFullDiskScanURL: URL?
    private(set) var sessionFolders: [SessionFolder] = []
    var errorMessage: String?

    private let scanner = DiskScanner()
    private let volumeDiscovery = VolumeDiscovery()
    private let fullDiskAccessChecker = FullDiskAccessChecker()
    private let previousScanStore = PreviousScanStore()
    private var scanSessionStore = ScanSessionStore()
    private var previousSummaries: [String: PreviousScanSummary] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var volumeRefreshTask: Task<Void, Never>?
    private var scanFallbackResult: ScanResult?
    private var activeScanID = UUID()
    @ObservationIgnored private var volumeObserverTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var activationObserverToken: NSObjectProtocol?

    init() {
        refreshVolumes()
        observeVolumeChanges()
        observeApplicationActivation()
    }

    deinit {
        scanTask?.cancel()
        volumeRefreshTask?.cancel()
        for token in volumeObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        if let activationObserverToken {
            NotificationCenter.default.removeObserver(activationObserverToken)
        }
    }

    var currentNode: FileNode? {
        navigationPath.last ?? (isScanning ? progress.previewRoot : nil)
    }
    var canNavigateBack: Bool { !isScanning && navigationPath.count > 1 }
    var isRequestingFullDiskAccess: Bool { pendingFullDiskScanURL != nil }

    var estimatedScanFraction: Double? {
        guard isScanning, let scanningURL else { return nil }
        let standardizedPath = scanningURL.standardizedFileURL.path
        let targetBytes = volumes.first {
            $0.url.standardizedFileURL.path == standardizedPath
        }?.usedCapacity ?? scanFallbackResult?.root.size ?? 0
        guard targetBytes > 0 else { return nil }
        return min(max(Double(progress.mappedBytes) / Double(targetBytes), 0), 0.99)
    }

    func volumeForChart(node: FileNode) -> VolumeInfo? {
        let rootPath = node.url.standardizedFileURL.path
        return volumes.first { $0.url.standardizedFileURL.path == rootPath }
    }

    func refreshVolumes() {
        volumeRefreshTask?.cancel()
        isDiscoveringVolumes = true
        let discovery = volumeDiscovery
        let store = previousScanStore

        volumeRefreshTask = Task { [weak self] in
            let startupTask = Task.detached(priority: .userInitiated) {
                discovery.startupVolume()
            }
            let volumesTask = Task.detached(priority: .utility) {
                discovery.mountedVolumes()
            }
            let summariesTask = Task.detached(priority: .utility) {
                store.load()
            }

            if let startupVolume = await startupTask.value,
               !Task.isCancelled,
               self?.selectedVolumeOverview == nil {
                self?.selectedVolumeOverview = startupVolume
            }

            let discoveredVolumes = await volumesTask.value
            let summaries = await summariesTask.value
            guard let self, !Task.isCancelled else { return }
            volumes = discoveredVolumes
            previousSummaries = summaries

            if let selectedVolumeOverview,
               let refreshedSelection = discoveredVolumes.first(where: {
                   $0.url.standardizedFileURL.path
                       == selectedVolumeOverview.url.standardizedFileURL.path
               }) {
                self.selectedVolumeOverview = refreshedSelection
            } else if selectedVolumeOverview == nil {
                self.selectedVolumeOverview = preferredStartupVolume(in: discoveredVolumes)
            }
            updatePreviousScanPresentation()
            isDiscoveringVolumes = false
            volumeRefreshTask = nil
        }
    }

    func selectVolume(_ volume: VolumeInfo) {
        if cachedResult(for: volume) != nil {
            viewCachedResult(at: volume.url)
        } else {
            showVolumeOverview(volume)
        }
    }

    func selectSessionFolder(_ folder: SessionFolder) {
        selectedVolumeOverview = nil
        previousScanSummary = nil
        previousScanRoot = nil
        if cachedResult(for: folder) != nil {
            viewCachedResult(at: folder.url)
        } else {
            scan(folder.url)
        }
    }

    func cachedResult(for volume: VolumeInfo) -> ScanResult? {
        scanSessionStore.result(for: volume.url)
    }

    func cachedResult(for folder: SessionFolder) -> ScanResult? {
        scanSessionStore.result(for: folder.url)
    }

    func cachedResult(at url: URL) -> ScanResult? {
        scanSessionStore.result(for: url)
    }

    func viewCachedResult(at url: URL) {
        guard let cachedResult = cachedResult(at: url) else {
            scan(url)
            return
        }

        cancelScan()
        result = cachedResult
        navigationPath = [cachedResult.root]
        errorMessage = nil
        if let volume = volumes.first(where: {
            $0.url.standardizedFileURL.path == url.standardizedFileURL.path
        }) {
            selectedVolumeOverview = volume
            updatePreviousScanPresentation()
        }
    }

    func removeSessionFolder(_ folder: SessionFolder) {
        let folderPath = folder.url.standardizedFileURL.path
        sessionFolders.removeAll { $0.id == folder.id }
        scanSessionStore.removeResult(for: folder.url)

        if scanningURL?.standardizedFileURL.path == folderPath {
            cancelScan()
        }
        if result?.root.url.standardizedFileURL.path == folderPath {
            result = nil
            navigationPath = []
        }
    }

    func showDiskList() {
        cancelScan()
        pendingFullDiskScanURL = nil
        result = nil
        navigationPath = []
        progress = ScanProgress()
        selectedVolumeOverview = preferredStartupVolume(in: volumes)
        updatePreviousScanPresentation()
        refreshVolumes()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to inspect"
        panel.prompt = "Scan Folder"
        panel.message = "SpaceLens reads file sizes only. It never changes your files."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let folder = SessionFolder(url: url)
        if !sessionFolders.contains(folder) {
            sessionFolders.append(folder)
        }
        selectedVolumeOverview = nil
        previousScanSummary = nil
        previousScanRoot = nil
        scan(folder.url)
    }

    func scan(_ url: URL) {
        if let volume = volumes.first(where: {
            $0.url.standardizedFileURL.path == url.standardizedFileURL.path
        }) {
            selectedVolumeOverview = volume
            updatePreviousScanPresentation()
        }
        if fullDiskAccessChecker.status(for: url) == .needsUserApproval {
            pendingFullDiskScanURL = url
            return
        }
        startScan(url)
    }

    func scanPendingDiskWithCurrentAccess() {
        guard let url = pendingFullDiskScanURL else { return }
        pendingFullDiskScanURL = nil
        startScan(url)
    }

    func cancelPendingDiskScan() {
        pendingFullDiskScanURL = nil
    }

    func resumePendingDiskScanIfAuthorized() {
        guard let url = pendingFullDiskScanURL,
              fullDiskAccessChecker.status(for: url) == .granted else { return }
        pendingFullDiskScanURL = nil
        startScan(url)
    }

    private func startScan(_ url: URL) {
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        let standardizedURL = url.standardizedFileURL
        scanFallbackResult = result?.root.url.standardizedFileURL.path == standardizedURL.path
            ? result
            : scanSessionStore.result(for: standardizedURL)
        scanningURL = url
        scanStartedAt = Date()
        isScanning = true
        let initialPreview = FileNode(
            url: standardizedURL,
            name: displayName(for: standardizedURL),
            size: 0,
            isDirectory: true,
            isReadable: true,
            children: [],
            itemCount: 1
        )
        progress = ScanProgress(currentPath: url.path, previewRoot: initialPreview)
        if let scanFallbackResult {
            result = scanFallbackResult
            navigationPath = [scanFallbackResult.root]
        } else {
            result = nil
            navigationPath = []
        }
        errorMessage = nil

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await scanner.scan(url: url) { progress in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.activeScanID == scanID,
                              self.isScanning else { return }
                        self.progress = progress
                    }
                }

                guard !Task.isCancelled, activeScanID == scanID else { return }
                self.result = result
                progress.previewRoot = nil
                scanFallbackResult = nil
                if volumes.contains(where: {
                    $0.url.standardizedFileURL.path == url.standardizedFileURL.path
                }) || sessionFolders.contains(where: {
                    $0.url.standardizedFileURL.path == url.standardizedFileURL.path
                }) {
                    scanSessionStore.store(result, for: url)
                }
                if let volume = volumes.first(where: {
                    $0.url.standardizedFileURL.path == url.standardizedFileURL.path
                }) {
                    let summary = PreviousScanSummary(result: result, volume: volume)
                    previousSummaries[summary.volumeIdentifier] = summary
                    previousScanSummary = summary
                    previousScanRoot = summary.makeRoot(at: volume.url)
                    let store = previousScanStore
                    Task.detached(priority: .utility) {
                        try? store.store(summary)
                    }
                }
                navigationPath = [result.root]
                isScanning = false
                scanningURL = nil
                scanStartedAt = nil
                scanTask = nil
            } catch {
                guard activeScanID == scanID else { return }
                let fallbackResult = scanFallbackResult
                isScanning = false
                scanningURL = nil
                scanStartedAt = nil
                progress.previewRoot = nil
                scanFallbackResult = nil
                scanTask = nil
                result = fallbackResult
                navigationPath = fallbackResult.map { [$0.root] } ?? []
                if error is CancellationError { return }
                if let failure = error as? ScanFailure, case .cancelled = failure {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelScan() {
        let fallbackResult = scanFallbackResult
        activeScanID = UUID()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanningURL = nil
        scanStartedAt = nil
        progress.previewRoot = nil
        scanFallbackResult = nil
        result = fallbackResult
        navigationPath = fallbackResult.map { [$0.root] } ?? []
    }

    func rescan() {
        guard let rootURL = result?.root.url ?? scanningURL else { return }
        scan(rootURL)
    }

    func showVolumeOverview(_ volume: VolumeInfo) {
        cancelScan()
        result = nil
        navigationPath = []
        selectedVolumeOverview = volume
        updatePreviousScanPresentation()
    }

    func navigate(into node: FileNode) {
        guard !isScanning, node.isDirectory, !node.children.isEmpty else { return }
        navigationPath.append(node)
    }

    func navigate(toBreadcrumbAt index: Int) {
        guard navigationPath.indices.contains(index) else { return }
        navigationPath = Array(navigationPath.prefix(index + 1))
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        navigationPath.removeLast()
    }

    func showInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func openInTerminal(_ node: FileNode) {
        let target = (node.isDirectory || node.isAggregate)
            ? node.url
            : node.url.deletingLastPathComponent()
        let terminalLocations = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ]

        guard let terminalPath = terminalLocations.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            errorMessage = "Terminal.app could not be found."
            return
        }
        let terminalURL = URL(fileURLWithPath: terminalPath)

        NSWorkspace.shared.open(
            [target],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeVolumeChanges() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]

        volumeObserverTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVolumes() }
            }
        }
    }

    private func observeApplicationActivation() {
        activationObserverToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumePendingDiskScanIfAuthorized()
            }
        }
    }

    private func displayName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func preferredStartupVolume(in volumes: [VolumeInfo]) -> VolumeInfo? {
        volumes.first { $0.url.standardizedFileURL.path == "/" }
            ?? volumes.first { !$0.isExternal && $0.isLocal }
            ?? volumes.first
    }

    private func updatePreviousScanPresentation() {
        guard let volume = selectedVolumeOverview,
              let summary = previousSummaries[volume.persistentIdentifier] else {
            previousScanSummary = nil
            previousScanRoot = nil
            return
        }
        previousScanSummary = summary
        previousScanRoot = summary.makeRoot(at: volume.url)
    }
}
