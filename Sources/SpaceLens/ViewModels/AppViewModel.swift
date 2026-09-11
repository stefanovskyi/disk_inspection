import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private(set) var selectedSection: AppSection = .storage
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
    private(set) var pendingRescanVolume: VolumeInfo?
    private(set) var sessionFolders: [SessionFolder] = []
    let aiCodingTools: AICodingToolsStore
    let aiModelsAndRuntimes: AIModelsAndRuntimesStore
    var errorMessage: String?

    private let scanner = DiskScanner()
    private let scanCoordinator: ScanCoordinator
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
        let scanCoordinator = ScanCoordinator()
        self.scanCoordinator = scanCoordinator
        aiCodingTools = AICodingToolsStore(scanCoordinator: scanCoordinator)
        aiModelsAndRuntimes = AIModelsAndRuntimesStore(scanCoordinator: scanCoordinator)
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
    var isRequestingRescan: Bool { pendingRescanVolume != nil }

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
            if !isScanning, result == nil, let selectedVolumeOverview {
                presentStoredResult(for: selectedVolumeOverview)
            }
            isDiscoveringVolumes = false
            volumeRefreshTask = nil
        }
    }

    func selectVolume(_ volume: VolumeInfo) {
        selectedSection = .storage
        if presentStoredResult(for: volume) {
            return
        } else {
            showVolumeOverview(volume)
            requestRescanConfirmation(for: volume)
        }
    }

    func selectSessionFolder(_ folder: SessionFolder) {
        selectedSection = .storage
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

        cancelAnalysesPreservingReports()
        cancelScan()
        selectedSection = .storage
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

    @discardableResult
    func viewPreviousScan(for volume: VolumeInfo) -> Bool {
        guard let summary = previousSummaries[volume.persistentIdentifier] else {
            return false
        }

        cancelAnalysesPreservingReports()
        cancelScan()
        selectedSection = .storage
        let previousResult = summary.makeResult(at: volume.url)
        selectedVolumeOverview = volume
        previousScanSummary = summary
        previousScanRoot = previousResult.root
        result = previousResult
        navigationPath = [previousResult.root]
        errorMessage = nil
        return true
    }

    func requestRescanConfirmation(for volume: VolumeInfo) {
        selectedVolumeOverview = volume
        updatePreviousScanPresentation()
        pendingRescanVolume = volume
    }

    func confirmPendingRescan() {
        guard let volume = pendingRescanVolume else { return }
        pendingRescanVolume = nil
        scan(volume.url)
    }

    func cancelPendingRescan() {
        pendingRescanVolume = nil
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
        cancelAnalysesPreservingReports()
        cancelScan()
        selectedSection = .storage
        pendingFullDiskScanURL = nil
        pendingRescanVolume = nil
        result = nil
        navigationPath = []
        progress = ScanProgress()
        selectedVolumeOverview = preferredStartupVolume(in: volumes)
        updatePreviousScanPresentation()
        if let selectedVolumeOverview {
            presentStoredResult(for: selectedVolumeOverview)
        }
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
        selectedSection = .storage
        scan(folder.url)
    }

    func scan(_ url: URL) {
        cancelAnalysesPreservingReports()
        selectedSection = .storage
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
        let scanID = UUID()
        scanCoordinator.begin(.storage, id: scanID) { [weak self] in
            self?.cancelScan(expectedID: scanID)
        }
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
                let result = try await scanner.scan(url: url, onProgress: { progress in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.activeScanID == scanID,
                              self.isScanning else { return }
                        self.progress = progress
                    }
                })

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
                scanCoordinator.finish(.storage, id: scanID)
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
                scanCoordinator.finish(.storage, id: scanID)
                if error is CancellationError { return }
                if let failure = error as? ScanFailure, case .cancelled = failure {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelScan() {
        cancelScan(expectedID: activeScanID)
    }

    private func cancelScan(expectedID: UUID) {
        guard activeScanID == expectedID else { return }
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
        scanCoordinator.finish(.storage, id: expectedID)
    }

    func rescan() {
        guard let rootURL = result?.root.url ?? scanningURL else { return }
        scan(rootURL)
    }

    var canRefreshCurrentSection: Bool {
        switch selectedSection {
        case .storage:
            result != nil && !isScanning
        case .aiCodingTools:
            !aiCodingTools.isRunning
        case .aiModelsAndRuntimes:
            !aiModelsAndRuntimes.isRunning
        }
    }

    func refreshCurrentSection() {
        switch selectedSection {
        case .storage:
            rescan()
        case .aiCodingTools:
            analyzeAICodingTools()
        case .aiModelsAndRuntimes:
            analyzeAIModelsAndRuntimes()
        }
    }

    func showVolumeOverview(_ volume: VolumeInfo) {
        cancelAnalysesPreservingReports()
        cancelScan()
        selectedSection = .storage
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
        openInTerminal(url: target)
    }

    func showInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInTerminal(url: URL) {
        let target = url
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

    func showAICodingTools() {
        if isScanning {
            cancelScan()
        }
        aiModelsAndRuntimes.cancelPreservingReport()
        selectedSection = .aiCodingTools
    }

    func analyzeAICodingTools() {
        selectedSection = .aiCodingTools
        errorMessage = nil
        aiCodingTools.analyze()
    }

    func cancelAICodingToolsAnalysis() {
        aiCodingTools.cancelPreservingReport()
    }

    func chooseAICodingProjectRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose a project root"
        panel.prompt = "Add Project Root"
        panel.message = "SpaceLens checks this project for AI tool worktrees. It reads file metadata only."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        aiCodingTools.addProjectRoot(url)
    }

    func inspectAICodingNode(_ node: FileNode) {
        guard node.isDirectory, !node.isAggregate, node.isReadable else { return }
        addAndScanAICodingDirectory(node.url)
    }

    private func addAndScanAICodingDirectory(_ url: URL) {
        let folder = SessionFolder(url: url)
        if !sessionFolders.contains(folder) {
            sessionFolders.append(folder)
        }
        scan(url)
    }

    func showAIModelsAndRuntimes() {
        if isScanning {
            cancelScan()
        }
        aiCodingTools.cancelPreservingReport()
        selectedSection = .aiModelsAndRuntimes
    }

    func analyzeAIModelsAndRuntimes() {
        selectedSection = .aiModelsAndRuntimes
        errorMessage = nil
        aiModelsAndRuntimes.analyze()
    }

    func cancelAIModelsAndRuntimesAnalysis() {
        aiModelsAndRuntimes.cancelPreservingReport()
    }

    func chooseAdditionalAIModelRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder containing local AI models"
        panel.prompt = "Add Model Folder"
        panel.message = "SpaceLens looks for GGUF and SafeTensors model data. Analysis is read-only."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        aiModelsAndRuntimes.addRoot(url)
    }

    func inspectAIModelsDirectory(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        let folder = SessionFolder(url: url)
        if !sessionFolders.contains(folder) {
            sessionFolders.append(folder)
        }
        scan(url)
    }

    private func cancelAnalysesPreservingReports() {
        aiCodingTools.cancelPreservingReport()
        aiModelsAndRuntimes.cancelPreservingReport()
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

    @discardableResult
    private func presentStoredResult(for volume: VolumeInfo) -> Bool {
        if cachedResult(for: volume) != nil {
            viewCachedResult(at: volume.url)
            return true
        }
        return viewPreviousScan(for: volume)
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
