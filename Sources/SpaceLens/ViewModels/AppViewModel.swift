import AppKit
import Foundation
import Observation

private enum PendingFullDiskOperation {
    case scan(URL)
    case scanEverything(ScanEverythingPlan)
    case analysis(ScanEverythingAnalysis)
}

private enum NavigationLocation: Equatable {
    case storage(StorageNavigationLocation)
    case aiCodingTools(AICodingToolID?)
    case aiModelsAndRuntimes(AIModelRuntimeID?)
    case developerStorage(DeveloperEcosystemID?)
}

private struct StorageNavigationLocation: Equatable {
    let volume: VolumeInfo?
    let result: ScanResult?
    let scanPath: String?
    let navigationPath: [FileNode]

    var rootPath: String? { scanPath ?? result?.root.id ?? volume?.id }
    var showsScan: Bool { result != nil || scanPath != nil }
    var nodeIDs: [String] {
        navigationPath.isEmpty ? rootPath.map { [$0] } ?? [] : navigationPath.map(\.id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rootPath == rhs.rootPath && lhs.showsScan == rhs.showsScan && lhs.nodeIDs == rhs.nodeIDs
    }
}

/// A requested disk or folder scan. Progress lives on this object so that a
/// background scan only invalidates views that actually read it.
@MainActor
@Observable
final class StorageScanJob {
    let id = UUID()
    let url: URL
    let path: String
    let name: String
    let fallbackResult: ScanResult?
    fileprivate(set) var startedAt: Date?
    fileprivate(set) var progress: ScanProgress

    init(url: URL, name: String, fallbackResult: ScanResult?, progress: ScanProgress) {
        self.url = url
        path = url.standardizedFileURL.path
        self.name = name
        self.fallbackResult = fallbackResult
        self.progress = progress
    }
}

/// A requested Disc Scan or Analysis batch.
@MainActor
@Observable
final class ScanEverythingRun {
    let id = UUID()
    let plan: ScanEverythingPlan
    fileprivate(set) var startedAt: Date?
    fileprivate(set) var progress: ScanEverythingProgress

    init(plan: ScanEverythingPlan) {
        self.plan = plan
        progress = ScanEverythingProgress(totalSteps: plan.steps.count)
    }
}

struct ScanEverythingOutcome: Equatable, Sendable {
    let scope: ScanEverythingScope
    let summary: ScanEverythingSummary
}

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
    private(set) var storageScans: [StorageScanJob] = []
    private(set) var pendingScanEverythingPlan: ScanEverythingPlan?
    private(set) var scanEverythingRuns: [ScanEverythingRun] = []
    private(set) var lastScanEverythingOutcome: ScanEverythingOutcome?
    private(set) var pendingRescanVolume: VolumeInfo?
    private(set) var sessionFolders: [SessionFolder] = []
    let aiCodingTools: AICodingToolsStore
    let aiModelsAndRuntimes: AIModelsAndRuntimesStore
    let developerStorage: DeveloperStorageStore
    @ObservationIgnored let scanFacts = ScanFactRotation()
    var errorMessage: String?

    private let scanner: any VolumeScanning
    private let scanEverythingRunner: ScanEverythingRunner
    private let scanCoordinator: ScanCoordinator
    private let volumeDiscovery = VolumeDiscovery()
    private let fullDiskAccessChecker: FullDiskAccessChecker
    private let previousScanStore = PreviousScanStore()
    private let scanResultFinalizer = ScanResultFinalizer()
    private var scanSessionStore = ScanSessionStore()
    private var navigationHistory = NavigationHistory<NavigationLocation>()
    @ObservationIgnored private var isUpdatingNavigation = false
    private var previousSummaries: [String: PreviousScanSummary] = [:]
    @ObservationIgnored private var scanTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var volumeRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var volumeFinalizationTasks: [UUID: Task<Void, Never>] = [:]
    /// The location whose scan the storage page is following, if any.
    private var presentedScanPath: String?
    private var pendingFullDiskOperation: PendingFullDiskOperation?
    @ObservationIgnored private var volumeObserverTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var activationObserverToken: NSObjectProtocol?

    init(
        scanner: any VolumeScanning = DiskScanner(),
        scanEverythingRunner: ScanEverythingRunner = ScanEverythingRunner(),
        aiCodingToolsAnalyzer: any AICodingToolsAnalyzing = AICodingToolsAnalyzer(),
        aiModelsAndRuntimesAnalyzer: any AIModelsAndRuntimesAnalyzing = AIModelsAndRuntimesAnalyzer(),
        developerStorageAnalyzer: any DeveloperStorageAnalyzing = DeveloperStorageAnalyzer(),
        fullDiskAccessChecker: FullDiskAccessChecker = FullDiskAccessChecker(),
        maximumConcurrentActivities: Int = ScanCoordinator.defaultMaximumConcurrentActivities
    ) {
        let scanCoordinator = ScanCoordinator(maximumConcurrentActivities: maximumConcurrentActivities)
        self.scanner = scanner
        self.scanEverythingRunner = scanEverythingRunner
        self.fullDiskAccessChecker = fullDiskAccessChecker
        self.scanCoordinator = scanCoordinator
        aiCodingTools = AICodingToolsStore(
            analyzer: aiCodingToolsAnalyzer,
            scanCoordinator: scanCoordinator
        )
        aiModelsAndRuntimes = AIModelsAndRuntimesStore(
            analyzer: aiModelsAndRuntimesAnalyzer,
            scanCoordinator: scanCoordinator
        )
        developerStorage = DeveloperStorageStore(
            analyzer: developerStorageAnalyzer,
            scanCoordinator: scanCoordinator
        )
        refreshVolumes()
        observeVolumeChanges()
        observeApplicationActivation()
    }

    deinit {
        scanTasks.values.forEach { $0.cancel() }
        volumeRefreshTask?.cancel()
        volumeFinalizationTasks.values.forEach { $0.cancel() }
        for token in volumeObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        if let activationObserverToken {
            NotificationCenter.default.removeObserver(activationObserverToken)
        }
    }

    var presentedScan: StorageScanJob? {
        presentedScanPath.flatMap(scanJob(atPath:))
    }

    /// Whether the location shown on the storage page is being scanned right now.
    var isScanning: Bool { presentedScan != nil }

    var currentNode: FileNode? {
        navigationPath.last ?? presentedScan?.progress.previewRoot
    }
    var canNavigateBack: Bool { navigationHistory.canGoBack }
    var isRequestingFullDiskAccess: Bool { pendingFullDiskOperation != nil }
    var isRequestingScanEverything: Bool { pendingScanEverythingPlan != nil }
    var isRequestingRescan: Bool { pendingRescanVolume != nil }

    var canRequestDiscScan: Bool {
        !isDiscoveringVolumes
            && !remainingWork(in: ScanEverythingPlan(volumes: volumes)).steps.isEmpty
    }

    var canRequestAllAnalyses: Bool {
        !remainingWork(
            in: ScanEverythingPlan(volumes: [], analyses: ScanEverythingAnalysis.allCases)
        ).steps.isEmpty
    }

    /// A batch has this analysis queued or running.
    func isInScanEverything(_ analysis: ScanEverythingAnalysis) -> Bool {
        isInScanEverything(.analysis(analysis))
    }

    /// A batch has this volume queued or running.
    func isInScanEverything(_ volume: VolumeInfo) -> Bool {
        isInScanEverything(.volume(volume))
    }

    private func isInScanEverything(_ step: ScanEverythingStep) -> Bool {
        scanEverythingRuns.contains { run in
            run.plan.steps.contains { $0.id == step.id }
                && !run.progress.completedStepIDs.contains(step.id)
        }
    }

    func scanEverythingOperation(
        for analysis: ScanEverythingAnalysis
    ) -> ScanEverythingOperationProgress? {
        scanEverythingRuns.lazy.compactMap { $0.progress.operation(for: .analysis(analysis)) }.first
    }

    func isScanActive(at url: URL) -> Bool {
        scanJob(at: url) != nil
    }

    func isScanActive(on volume: VolumeInfo) -> Bool {
        isScanActive(at: volume.url) || isInScanEverything(volume)
    }

    func isAnalysisActive(_ analysis: ScanEverythingAnalysis) -> Bool {
        if isInScanEverything(analysis) { return true }
        return switch analysis {
        case .aiCodingTools: aiCodingTools.isRunning
        case .aiModelsAndRuntimes: aiModelsAndRuntimes.isRunning
        case .developerStorage: developerStorage.isRunning
        }
    }

    private func scanJob(at url: URL) -> StorageScanJob? {
        scanJob(atPath: url.standardizedFileURL.path)
    }

    private func scanJob(atPath path: String) -> StorageScanJob? {
        storageScans.first { $0.path == path }
    }

    private func volume(at url: URL) -> VolumeInfo? {
        let path = url.standardizedFileURL.path
        return volumes.first { $0.url.standardizedFileURL.path == path }
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
            if selectedSection == .storage, !isScanning, result == nil, let selectedVolumeOverview {
                // Refreshing mounted-volume metadata is not user navigation.
                isUpdatingNavigation = true
                presentActiveOrStoredScan(for: selectedVolumeOverview)
                isUpdatingNavigation = false
            }
            isDiscoveringVolumes = false
            volumeRefreshTask = nil
        }
    }

    func requestDiscScan() {
        let plan = ScanEverythingPlan(volumes: volumes, analyses: [])
        guard !plan.volumes.isEmpty else {
            errorMessage = "SpaceLens did not find any local disks to scan."
            return
        }
        requestScanEverything(plan)
    }

    func requestAllAnalyses() {
        requestScanEverything(
            ScanEverythingPlan(
                volumes: [],
                analyses: ScanEverythingAnalysis.allCases
            )
        )
    }

    private func requestScanEverything(_ plan: ScanEverythingPlan) {
        let plan = remainingWork(in: plan)
        guard !plan.steps.isEmpty else { return }
        guard verifyFullDiskAccess(for: .scanEverything(plan)) else { return }
        pendingScanEverythingPlan = plan
    }

    /// Drops work already queued or running so it is never measured twice at once.
    private func remainingWork(in plan: ScanEverythingPlan) -> ScanEverythingPlan {
        ScanEverythingPlan(
            volumes: plan.volumes.filter { !isScanActive(on: $0) },
            analyses: plan.analyses.filter { !isAnalysisActive($0) }
        )
    }

    func confirmScanEverything() {
        guard let plan = pendingScanEverythingPlan else { return }
        pendingScanEverythingPlan = nil
        guard verifyFullDiskAccess(for: .scanEverything(plan)) else { return }
        startScanEverything(plan)
    }

    func cancelScanEverythingConfirmation() {
        pendingScanEverythingPlan = nil
    }

    private func startScanEverything(_ plan: ScanEverythingPlan) {
        let plan = remainingWork(in: plan)
        guard !plan.steps.isEmpty else { return }
        let run = ScanEverythingRun(plan: plan)
        scanEverythingRuns.append(run)
        pendingFullDiskOperation = nil
        errorMessage = nil
        scanCoordinator.enqueue(.scanEverything, id: run.id) { [weak self, weak run] in
            guard let self, let run else { return }
            runScanEverything(run)
        }
    }

    private func runScanEverything(_ run: ScanEverythingRun) {
        run.startedAt = Date()
        let plan = run.plan
        let runner = scanEverythingRunner
        let requests = ScanEverythingRequests(
            aiCodingTools: .currentUser(projectRoots: aiCodingTools.projectRoots.map(\.url)),
            aiModelsAndRuntimes: .currentUser(
                additionalModelRoots: aiModelsAndRuntimes.additionalRoots.map(\.url)
            ),
            developerStorage: .currentUser(
                projectContainers: developerStorage.projectContainers.map(\.url)
            )
        )

        scanTasks[run.id] = Task { [weak self, weak run] in
            guard let self, let run else { return }
            do {
                let summary = try await runner.run(
                    plan: plan,
                    requests: requests,
                    onEvent: { [weak self, weak run] event in
                        guard let self, let run else { return }
                        await receiveScanEverythingEvent(event, run: run)
                    }
                )
                guard !Task.isCancelled, isTracked(run) else { return }
                removeScanEverythingRun(run)
                lastScanEverythingOutcome = ScanEverythingOutcome(scope: plan.scope, summary: summary)
                if let firstFailure = summary.outcomes.first(where: {
                    if case .failed = $0.status { return true }
                    return false
                }), case .failed(let message) = firstFailure.status {
                    if summary.failureCount == 1 {
                        errorMessage = "\(firstFailure.step.title) failed: \(message)"
                    } else {
                        errorMessage = "\(plan.scope.title) completed with \(summary.failureCount) problems. "
                            + "First: \(firstFailure.step.title) failed: \(message)"
                    }
                }
            } catch {
                guard isTracked(run) else { return }
                removeScanEverythingRun(run)
                if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func isTracked(_ run: ScanEverythingRun) -> Bool {
        scanEverythingRuns.contains { $0 === run }
    }

    private func removeScanEverythingRun(_ run: ScanEverythingRun) {
        scanEverythingRuns.removeAll { $0 === run }
        scanTasks[run.id] = nil
        scanCoordinator.finish(.scanEverything, id: run.id)
    }

    private func cancelScanEverything(_ run: ScanEverythingRun) {
        guard isTracked(run) else { return }
        scanTasks[run.id]?.cancel()
        removeScanEverythingRun(run)
        lastScanEverythingOutcome = nil
    }

    private func receiveScanEverythingEvent(
        _ event: ScanEverythingEvent,
        run: ScanEverythingRun
    ) async {
        guard isTracked(run) else { return }

        switch event {
        case .progress(let progress):
            guard progress.overallFraction >= run.progress.overallFraction else { return }
            run.progress = progress

        case .volumeCompleted(let volume, let result):
            storeCompletedVolumeScan(result, for: volume, presentWhenSelected: true)

        case .aiCodingToolsCompleted(let report):
            aiCodingTools.installReport(report)

        case .aiModelsAndRuntimesCompleted(let report):
            aiModelsAndRuntimes.installReport(report)

        case .developerStorageCompleted(let report):
            developerStorage.installReport(report)

        case .stepFailed:
            break
        }
    }

    func selectVolume(_ volume: VolumeInfo) {
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        selectedSection = .storage
        if presentActiveOrStoredScan(for: volume) {
            return
        }
        showVolumeOverview(volume)
        if !isInScanEverything(volume) {
            requestRescanConfirmation(for: volume)
        }
    }

    func selectSessionFolder(_ folder: SessionFolder) {
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        selectedSection = .storage
        selectedVolumeOverview = nil
        previousScanSummary = nil
        previousScanRoot = nil
        if let job = scanJob(at: folder.url) {
            present(job)
        } else if cachedResult(for: folder) != nil {
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
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        guard let cachedResult = cachedResult(at: url) else {
            scan(url)
            return
        }

        selectedSection = .storage
        presentedScanPath = scanJob(at: url)?.path
        result = cachedResult
        navigationPath = [cachedResult.root]
        errorMessage = nil
        if let volume = volume(at: url) {
            selectedVolumeOverview = volume
            updatePreviousScanPresentation()
        } else {
            selectedVolumeOverview = nil
            previousScanSummary = nil
            previousScanRoot = nil
        }
    }

    @discardableResult
    func viewPreviousScan(for volume: VolumeInfo) -> Bool {
        guard let summary = previousSummaries[volume.persistentIdentifier] else {
            return false
        }
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }

        selectedSection = .storage
        presentedScanPath = scanJob(at: volume.url)?.path
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
        guard !isScanActive(on: volume) else { return }
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
        navigationHistory.removeAll {
            if case .storage(let location) = $0 { return location.rootPath == folderPath }
            return false
        }
        sessionFolders.removeAll { $0.id == folder.id }
        scanSessionStore.removeResult(for: folder.url)

        if let job = scanJob(atPath: folderPath) {
            cancelStorageScan(job)
        }
        if result?.root.url.standardizedFileURL.path == folderPath {
            result = nil
            navigationPath = []
        }
    }

    func showDiskList() {
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        selectedSection = .storage
        pendingFullDiskOperation = nil
        pendingScanEverythingPlan = nil
        pendingRescanVolume = nil
        presentedScanPath = nil
        result = nil
        navigationPath = []
        selectedVolumeOverview = preferredStartupVolume(in: volumes)
        updatePreviousScanPresentation()
        if let selectedVolumeOverview {
            presentActiveOrStoredScan(for: selectedVolumeOverview)
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
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
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
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        selectedSection = .storage
        let volume = volume(at: url)
        if let volume {
            selectedVolumeOverview = volume
            updatePreviousScanPresentation()
        } else {
            selectedVolumeOverview = nil
            previousScanSummary = nil
            previousScanRoot = nil
        }
        if let job = scanJob(at: url) {
            present(job)
            return
        }
        if let volume, isInScanEverything(volume) {
            showVolumeOverview(volume)
            return
        }
        guard verifyFullDiskAccess(for: .scan(url)) else { return }
        startScan(url)
    }

    func cancelPendingFullDiskOperation() {
        pendingFullDiskOperation = nil
    }

    func resumePendingOperationIfAuthorized() {
        guard fullDiskAccessChecker.status() == .granted,
              let operation = pendingFullDiskOperation else { return }
        pendingFullDiskOperation = nil

        switch operation {
        case .scan(let url):
            startScan(url)
        case .scanEverything(let plan):
            pendingScanEverythingPlan = plan
        case .analysis(let analysis):
            startAnalysis(analysis)
        }
    }

    private func verifyFullDiskAccess(for operation: PendingFullDiskOperation) -> Bool {
        guard fullDiskAccessChecker.status() == .granted else {
            pendingFullDiskOperation = operation
            return false
        }
        pendingFullDiskOperation = nil
        return true
    }

    private func startScan(_ url: URL) {
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        if let job = scanJob(at: url) {
            present(job)
            return
        }
        let standardizedURL = url.standardizedFileURL
        let fallbackResult = result?.root.url.standardizedFileURL.path == standardizedURL.path
            ? result
            : scanSessionStore.result(for: standardizedURL)
        let initialPreview = FileNode(
            url: standardizedURL,
            name: displayName(for: standardizedURL),
            size: 0,
            isDirectory: true,
            isReadable: true,
            children: [],
            itemCount: 1
        )
        let job = StorageScanJob(
            url: url,
            name: volume(at: url)?.name ?? initialPreview.name,
            fallbackResult: fallbackResult,
            progress: ScanProgress(currentPath: url.path, previewRoot: initialPreview)
        )
        storageScans.append(job)
        present(job)
        errorMessage = nil
        scanCoordinator.enqueue(.storage, id: job.id) { [weak self, weak job] in
            guard let self, let job else { return }
            runStorageScan(job)
        }
    }

    private func runStorageScan(_ job: StorageScanJob) {
        job.startedAt = Date()
        let scanner = scanner
        scanTasks[job.id] = Task { [weak self, weak job] in
            guard let self, let job else { return }
            do {
                let result = try await scanner.scan(url: job.url, onProgress: { [weak self, weak job] progress in
                    Task { @MainActor [weak self, weak job] in
                        guard let self, let job, self.isTracked(job) else { return }
                        job.progress = progress
                    }
                })

                guard !Task.isCancelled, isTracked(job) else { return }
                if let volume = volume(at: job.url) {
                    storeCompletedVolumeScan(result, for: volume, presentWhenSelected: false)
                } else if sessionFolders.contains(where: { $0.id == job.path }) {
                    scanSessionStore.store(result, for: job.url)
                }
                if presentedScanPath == job.path {
                    presentedScanPath = nil
                    self.result = result
                    navigationPath = [result.root]
                }
                removeStorageScan(job)
            } catch {
                guard isTracked(job) else { return }
                withdrawPresentation(of: job)
                removeStorageScan(job)
                if error is CancellationError { return }
                if let failure = error as? ScanFailure, case .cancelled = failure {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Shows the scan's live state on the storage page without interrupting it.
    private func present(_ job: StorageScanJob) {
        selectedSection = .storage
        presentedScanPath = job.path
        result = job.fallbackResult
        navigationPath = job.fallbackResult.map { [$0.root] } ?? []
    }

    private func withdrawPresentation(of job: StorageScanJob) {
        guard presentedScanPath == job.path else { return }
        presentedScanPath = nil
        result = job.fallbackResult
        navigationPath = job.fallbackResult.map { [$0.root] } ?? []
    }

    private func isTracked(_ job: StorageScanJob) -> Bool {
        storageScans.contains { $0 === job }
    }

    private func removeStorageScan(_ job: StorageScanJob) {
        storageScans.removeAll { $0 === job }
        scanTasks[job.id] = nil
        scanCoordinator.finish(.storage, id: job.id)
    }

    private func cancelStorageScan(_ job: StorageScanJob) {
        guard isTracked(job) else { return }
        scanTasks[job.id]?.cancel()
        withdrawPresentation(of: job)
        removeStorageScan(job)
    }

    private func storeCompletedVolumeScan(
        _ result: ScanResult,
        for volume: VolumeInfo,
        presentWhenSelected: Bool
    ) {
        scanSessionStore.store(result, for: volume.url)

        let volumePath = volume.url.standardizedFileURL.path
        let showsThisVolume = self.result.map { $0.root.url.standardizedFileURL.path == volumePath } ?? true
        if selectedVolumeOverview?.url.standardizedFileURL.path == volumePath,
           presentWhenSelected, selectedSection == .storage, !isScanning, showsThisVolume {
            self.result = result
            navigationPath = [result.root]
        }

        let finalizationID = UUID()
        let finalizer = scanResultFinalizer
        volumeFinalizationTasks[finalizationID] = Task { [weak self] in
            let summary = await finalizer.finalize(result, for: volume)
            guard let self else { return }
            previousSummaries[summary.volumeIdentifier] = summary
            if selectedVolumeOverview?.url.standardizedFileURL.path
                == volume.url.standardizedFileURL.path {
                previousScanSummary = summary
                previousScanRoot = summary.makeRoot(at: volume.url)
            }
            volumeFinalizationTasks[finalizationID] = nil
        }
    }

    func rescan() {
        guard let rootURL = result?.root.url ?? presentedScan?.url else { return }
        scan(rootURL)
    }

    var canRefreshCurrentSection: Bool {
        switch selectedSection {
        case .storage:
            guard let result, !isScanning else { return false }
            return volume(at: result.root.url).map { !isInScanEverything($0) } ?? true
        case .aiCodingTools:
            return !isAnalysisActive(.aiCodingTools)
        case .aiModelsAndRuntimes:
            return !isAnalysisActive(.aiModelsAndRuntimes)
        case .developerStorage:
            return !isAnalysisActive(.developerStorage)
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
        case .developerStorage:
            analyzeDeveloperStorage()
        }
    }

    func showVolumeOverview(_ volume: VolumeInfo) {
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        selectedSection = .storage
        presentedScanPath = nil
        result = nil
        navigationPath = []
        selectedVolumeOverview = volume
        updatePreviousScanPresentation()
    }

    func navigate(into node: FileNode) {
        guard !isScanning, node.isDirectory, !node.children.isEmpty,
              let currentNode, node.id != currentNode.id,
              let destination = navigationNode(withID: node.id, under: currentNode) else { return }
        updateNavigation {
            navigationPath.append(destination)
        }
    }

    func navigate(toBreadcrumbAt index: Int) {
        guard navigationPath.indices.contains(index) else { return }
        updateNavigation {
            navigationPath = Array(navigationPath.prefix(index + 1))
        }
    }

    func navigateBack() {
        guard let location = navigationHistory.goBack() else { return }
        restoreNavigation(location)
    }

    private var navigationLocation: NavigationLocation {
        switch selectedSection {
        case .storage:
            return .storage(StorageNavigationLocation(
                volume: selectedVolumeOverview,
                result: result,
                scanPath: presentedScanPath,
                navigationPath: navigationPath
            ))
        case .aiCodingTools: return .aiCodingTools(aiCodingTools.selectedToolID)
        case .aiModelsAndRuntimes: return .aiModelsAndRuntimes(aiModelsAndRuntimes.selectedRuntimeID)
        case .developerStorage: return .developerStorage(developerStorage.selectedEcosystemID)
        }
    }

    /// Nested actions (such as selecting a cached folder) form one history entry.
    private func updateNavigation(_ update: () -> Void) {
        let previous = beginNavigation()
        defer { finishNavigation(from: previous) }
        update()
    }

    private func beginNavigation() -> NavigationLocation? {
        guard !isUpdatingNavigation else { return nil }
        isUpdatingNavigation = true
        return navigationLocation
    }

    private func finishNavigation(from previous: NavigationLocation?) {
        guard let previous else { return }
        navigationHistory.record(from: previous, to: navigationLocation)
        isUpdatingNavigation = false
    }

    private func restoreNavigation(_ location: NavigationLocation) {
        switch location {
        case .aiCodingTools(let id):
            selectedSection = .aiCodingTools
            aiCodingTools.selectTool(id)
        case .aiModelsAndRuntimes(let id):
            selectedSection = .aiModelsAndRuntimes
            aiModelsAndRuntimes.selectRuntime(id)
        case .developerStorage(let id):
            selectedSection = .developerStorage
            developerStorage.selectEcosystem(id)
        case .storage(let location):
            selectedSection = .storage
            selectedVolumeOverview = location.volume
            updatePreviousScanPresentation()
            presentedScanPath = nil
            result = nil
            navigationPath = []
            guard location.showsScan, let rootPath = location.rootPath else { return }
            let url = URL(fileURLWithPath: rootPath)
            if let job = scanJob(atPath: rootPath) {
                present(job)
            } else {
                result = cachedResult(at: url) ?? location.result
            }
            if let result {
                // A rescan can remove descendants. Stop at the deepest surviving folder.
                navigationPath = [result.root]
                for id in location.nodeIDs.dropFirst() {
                    guard let parent = navigationPath.last,
                          let node = navigationNode(withID: id, under: parent) else { break }
                    navigationPath.append(node)
                }
            }
        }
    }

    /// Chart clicks can jump several levels, so history paths need not list
    /// every ancestor. Resolve only the components along the requested path.
    private func navigationNode(withID id: String, under root: FileNode) -> FileNode? {
        if id == root.id { return root }
        guard id.hasPrefix(root.id == "/" ? "/" : root.id + "/") else { return nil }
        var node = root
        for name in id.dropFirst(root.id.count).split(separator: "/") {
            guard let child = node.children.first(where: { !$0.isAggregate && $0.name == name }) else { return nil }
            node = child
        }
        return node
    }

    func selectAICodingTool(_ id: AICodingToolID) {
        updateNavigation { aiCodingTools.selectTool(id) }
    }

    func selectAIModelRuntime(_ id: AIModelRuntimeID) {
        updateNavigation { aiModelsAndRuntimes.selectRuntime(id) }
    }

    func selectDeveloperEcosystem(_ id: DeveloperEcosystemID) {
        updateNavigation { developerStorage.selectEcosystem(id) }
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
        updateNavigation { selectedSection = .aiCodingTools }
    }

    func analyzeAICodingTools() {
        showAICodingTools()
        errorMessage = nil
        requestAnalysis(.aiCodingTools)
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
        analyzeAICodingTools()
    }

    func removeAICodingProjectRoot(_ root: AICodingProjectRoot) {
        let shouldAnalyze = aiCodingTools.isRunning || aiCodingTools.state.report != nil
        aiCodingTools.removeProjectRoot(root)
        if shouldAnalyze { analyzeAICodingTools() }
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
        updateNavigation { selectedSection = .aiModelsAndRuntimes }
    }

    func analyzeAIModelsAndRuntimes() {
        showAIModelsAndRuntimes()
        errorMessage = nil
        requestAnalysis(.aiModelsAndRuntimes)
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
        analyzeAIModelsAndRuntimes()
    }

    func removeAdditionalAIModelRoot(_ root: AIModelsAdditionalRoot) {
        let shouldAnalyze = aiModelsAndRuntimes.isRunning
            || aiModelsAndRuntimes.state.report != nil
        aiModelsAndRuntimes.removeRoot(root)
        if shouldAnalyze { analyzeAIModelsAndRuntimes() }
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

    func showDeveloperStorage() {
        updateNavigation { selectedSection = .developerStorage }
    }

    func analyzeDeveloperStorage() {
        showDeveloperStorage()
        errorMessage = nil
        requestAnalysis(.developerStorage)
    }

    func chooseDeveloperProjectsFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a projects folder"
        panel.prompt = "Add Projects Folder"
        panel.message = "Add an external or custom location beyond SpaceLens’s automatic home-folder discovery. Analysis is read-only."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let shouldAnalyze = developerStorage.state.report != nil
        developerStorage.addProjectContainer(url)
        if shouldAnalyze { analyzeDeveloperStorage() }
    }

    func removeDeveloperProjectContainer(_ container: DeveloperProjectContainer) {
        let shouldAnalyze = developerStorage.isRunning || developerStorage.state.report != nil
        developerStorage.removeProjectContainer(container)
        if shouldAnalyze { analyzeDeveloperStorage() }
    }

    func inspectDeveloperStorageDirectory(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        let folder = SessionFolder(url: url)
        if !sessionFolders.contains(folder) { sessionFolders.append(folder) }
        scan(url)
    }

    private func requestAnalysis(_ analysis: ScanEverythingAnalysis) {
        guard !isInScanEverything(analysis) else { return }
        guard verifyFullDiskAccess(for: .analysis(analysis)) else {
            cancelAnalysis(analysis)
            return
        }
        startAnalysis(analysis)
    }

    private func startAnalysis(_ analysis: ScanEverythingAnalysis) {
        switch analysis {
        case .aiCodingTools:
            aiCodingTools.analyze()
        case .aiModelsAndRuntimes:
            aiModelsAndRuntimes.analyze()
        case .developerStorage:
            developerStorage.analyze()
        }
    }

    private func cancelAnalysis(_ analysis: ScanEverythingAnalysis) {
        switch analysis {
        case .aiCodingTools:
            aiCodingTools.cancelPreservingReport()
        case .aiModelsAndRuntimes:
            aiModelsAndRuntimes.cancelPreservingReport()
        case .developerStorage:
            developerStorage.cancelPreservingReport()
        }
    }

    func cancel(_ activity: ScanActivity) {
        switch activity.target {
        case .storage(let path):
            if let job = scanJob(atPath: path) { cancelStorageScan(job) }
        case .analysis(let analysis):
            cancelAnalysis(analysis)
        case .batch(let id):
            if let run = scanEverythingRuns.first(where: { $0.id == id }) { cancelScanEverything(run) }
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
                self?.resumePendingOperationIfAuthorized()
            }
        }
    }

    private func displayName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func preferredStartupVolume(in volumes: [VolumeInfo]) -> VolumeInfo? {
        volumes.first(where: \.isStartupVolume)
            ?? volumes.first { !$0.isExternal && $0.isLocal }
            ?? volumes.first
    }

    @discardableResult
    private func presentActiveOrStoredScan(for volume: VolumeInfo) -> Bool {
        if let job = scanJob(at: volume.url) {
            selectedVolumeOverview = volume
            updatePreviousScanPresentation()
            present(job)
            return true
        }
        return presentStoredResult(for: volume)
    }

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

// MARK: - Sidebar progress

extension AppViewModel {
    /// Tracks only starts and finishes, so readers ignore per-scan progress updates.
    var activityCount: Int {
        var count = scanEverythingRuns.count + storageScans.count
        if aiCodingTools.isRunning { count += 1 }
        if aiModelsAndRuntimes.isRunning { count += 1 }
        if developerStorage.isRunning { count += 1 }
        return count
    }

    /// The refresh behind results already on the storage page, if any.
    var storageRefreshSource: ScanFactsSource? {
        if isScanning { return result == nil ? nil : .presentedScan }
        if let result {
            guard let volume = volume(at: result.root.url), isInScanEverything(volume) else { return nil }
            return .volume(volume)
        }
        guard let selectedVolumeOverview, isInScanEverything(selectedVolumeOverview) else { return nil }
        return .volume(selectedVolumeOverview)
    }

    /// When the work started, or `nil` while it is queued. Reads no progress, so
    /// callers don't redraw on every update.
    func startedAt(for source: ScanFactsSource) -> Date? {
        switch source {
        case .presentedScan:
            return presentedScan?.startedAt
        case .volume(let volume):
            return scanEverythingStartedAt(for: .volume(volume))
        case .analysis(.aiCodingTools) where aiCodingTools.isRunning:
            return aiCodingTools.startedAt
        case .analysis(.aiModelsAndRuntimes) where aiModelsAndRuntimes.isRunning:
            return aiModelsAndRuntimes.startedAt
        case .analysis(.developerStorage) where developerStorage.isRunning:
            return developerStorage.startedAt
        case .analysis(let analysis):
            return scanEverythingStartedAt(for: .analysis(analysis))
        }
    }

    private func scanEverythingStartedAt(for step: ScanEverythingStep) -> Date? {
        scanEverythingRuns.first { $0.progress.operation(for: step) != nil }?.startedAt
    }

    /// The progress a facts page shows, including work running inside a batch.
    func activity(for source: ScanFactsSource) -> ScanActivity? {
        switch source {
        case .presentedScan:
            return presentedScan.map(activity(for:))
        case .volume(let volume):
            return scanEverythingActivity(
                step: .volume(volume),
                target: .storage(path: volume.url.standardizedFileURL.path),
                systemImage: volume.isExternal ? "externaldrive" : "internaldrive",
                title: volume.name
            )
        case .analysis(.aiCodingTools) where aiCodingTools.isRunning:
            return aiCodingToolsActivity
        case .analysis(.aiModelsAndRuntimes) where aiModelsAndRuntimes.isRunning:
            return aiModelsActivity
        case .analysis(.developerStorage) where developerStorage.isRunning:
            return developerStorageActivity
        case .analysis(let analysis):
            return scanEverythingActivity(
                step: .analysis(analysis),
                target: .analysis(analysis),
                systemImage: "chart.bar.xaxis",
                title: analysis.title
            )
        }
    }

    private func scanEverythingActivity(
        step: ScanEverythingStep,
        target: ScanActivity.Target,
        systemImage: String,
        title: String
    ) -> ScanActivity? {
        guard let run = scanEverythingRuns.first(where: { run in
            run.plan.steps.contains { $0.id == step.id }
                && !run.progress.completedStepIDs.contains(step.id)
        }) else { return nil }
        guard let operation = run.progress.operation(for: step) else {
            return ScanActivity(
                target: target,
                systemImage: systemImage,
                title: title,
                status: ScanActivity.waitingStatus,
                detail: "Queued",
                startedAt: nil
            )
        }
        return ScanActivity(
            target: target,
            systemImage: systemImage,
            title: title,
            status: step.title,
            detail: "\(operation.itemsScanned.formatted()) items",
            location: operation.currentLocationName,
            currentPath: operation.currentPath,
            fraction: operation.fraction,
            mappedBytes: operation.mappedBytes,
            itemsScanned: operation.itemsScanned,
            startedAt: run.startedAt
        )
    }

    /// Everything queued or running, for the sidebar progress panel.
    var activities: [ScanActivity] {
        var activities = scanEverythingRuns.map(activity(for:))
        activities += storageScans.map(activity(for:))
        if aiCodingTools.isRunning { activities.append(aiCodingToolsActivity) }
        if aiModelsAndRuntimes.isRunning { activities.append(aiModelsActivity) }
        if developerStorage.isRunning { activities.append(developerStorageActivity) }
        return ScanActivity.ordered(activities)
    }

    private func activity(for job: StorageScanJob) -> ScanActivity {
        let progress = job.progress
        let targetBytes = volumes.first {
            $0.url.standardizedFileURL.path == job.path
        }?.usedCapacity ?? job.fallbackResult?.root.size ?? 0
        return ScanActivity(
            target: .storage(path: job.path),
            systemImage: volumes.contains { $0.url.standardizedFileURL.path == job.path }
                ? "internaldrive"
                : "folder",
            title: job.name,
            status: job.startedAt == nil
                ? ScanActivity.waitingStatus
                : "Scanning · \(StorageFormatters.bytes(progress.mappedBytes))",
            detail: "\(progress.itemsScanned.formatted()) items",
            currentPath: progress.currentPath,
            fraction: targetBytes > 0
                ? min(max(Double(progress.mappedBytes) / Double(targetBytes), 0), 0.99)
                : nil,
            mappedBytes: progress.mappedBytes,
            itemsScanned: progress.itemsScanned,
            startedAt: job.startedAt
        )
    }

    private func activity(for run: ScanEverythingRun) -> ScanActivity {
        let progress = run.progress
        let operations = progress.activeOperationsInStableOrder
        let onlyOperation = operations.count == 1 ? operations[0] : nil
        return ScanActivity(
            target: .batch(run.id),
            systemImage: run.plan.scope == .analysis ? "chart.bar.xaxis" : "internaldrive",
            title: run.plan.scope == .analysis ? "Running Analysis" : "Scanning Discs",
            status: batchStatus(run),
            detail: "\(progress.completedStepIDs.count) of \(progress.totalSteps) complete",
            location: onlyOperation?.currentLocationName,
            currentPath: onlyOperation?.currentPath,
            fraction: progress.overallFraction,
            startedAt: run.startedAt
        )
    }

    private func batchStatus(_ run: ScanEverythingRun) -> String {
        guard run.startedAt != nil else { return ScanActivity.waitingStatus }
        let progress = run.progress
        if progress.activeVolumeCount > 1 {
            return "Scanning \(progress.activeVolumeCount) disks"
        }
        if let operation = progress.activeOperationsInStableOrder.first {
            return operation.step.title
        }
        return progress.completedStepIDs.count == progress.totalSteps
            ? "Finishing \(run.plan.scope.title)"
            : "Preparing \(run.plan.scope.title)"
    }

    private func analysisStatus(current: String?, placeholder: String, mappedBytes: Int64) -> String {
        guard let current else { return placeholder }
        return "\(current) · \(StorageFormatters.bytes(mappedBytes))"
    }

    private var aiCodingToolsActivity: ScanActivity {
        let progress = aiCodingTools.progress
        return ScanActivity(
            target: .analysis(.aiCodingTools),
            systemImage: "wand.and.stars",
            title: ScanEverythingAnalysis.aiCodingTools.title,
            status: aiCodingTools.isQueued
                ? ScanActivity.waitingStatus
                : analysisStatus(
                    current: progress.currentTool?.displayName,
                    placeholder: "Finding known locations",
                    mappedBytes: progress.mappedBytes
                ),
            detail: "\(progress.itemsScanned.formatted()) items",
            location: progress.currentLocationName.isEmpty ? nil : progress.currentLocationName,
            currentPath: progress.currentPath.isEmpty ? nil : progress.currentPath,
            fraction: progress.fractionCompleted,
            mappedBytes: progress.mappedBytes,
            itemsScanned: progress.itemsScanned,
            startedAt: aiCodingTools.startedAt
        )
    }

    private var aiModelsActivity: ScanActivity {
        let progress = aiModelsAndRuntimes.progress
        return ScanActivity(
            target: .analysis(.aiModelsAndRuntimes),
            systemImage: "cpu",
            title: ScanEverythingAnalysis.aiModelsAndRuntimes.title,
            status: aiModelsAndRuntimes.isQueued
                ? ScanActivity.waitingStatus
                : analysisStatus(
                    current: progress.currentRuntime?.displayName,
                    placeholder: "Finding known locations",
                    mappedBytes: progress.mappedBytes
                ),
            detail: "\(progress.itemsScanned.formatted()) items",
            location: progress.currentLocationName,
            currentPath: progress.currentPath,
            fraction: progress.fractionCompleted,
            mappedBytes: progress.mappedBytes,
            itemsScanned: progress.itemsScanned,
            startedAt: aiModelsAndRuntimes.startedAt
        )
    }

    private var developerStorageActivity: ScanActivity {
        let progress = developerStorage.progress
        return ScanActivity(
            target: .analysis(.developerStorage),
            systemImage: "hammer",
            title: ScanEverythingAnalysis.developerStorage.title,
            status: developerStorage.isQueued
                ? ScanActivity.waitingStatus
                : analysisStatus(
                    current: progress.currentEcosystem?.displayName,
                    placeholder: "Discovering artifacts",
                    mappedBytes: progress.mappedBytes
                ),
            detail: "\(progress.itemsScanned.formatted()) items",
            location: progress.currentLocationName,
            currentPath: progress.currentPath,
            fraction: progress.fractionCompleted,
            mappedBytes: progress.mappedBytes,
            itemsScanned: progress.itemsScanned,
            startedAt: developerStorage.startedAt
        )
    }
}
