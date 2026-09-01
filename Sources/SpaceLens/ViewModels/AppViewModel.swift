import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var result: ScanResult?
    @Published private(set) var navigationPath: [FileNode] = []
    @Published private(set) var isScanning = false
    @Published private(set) var progress = ScanProgress()
    @Published private(set) var scanningURL: URL?
    @Published private(set) var scanStartedAt: Date?
    @Published private(set) var pendingFullDiskScanURL: URL?
    @Published private(set) var sessionFolders: [SessionFolder] = []
    @Published private(set) var pendingScanChoice: PendingScanChoice?
    @Published var hoveredNode: FileNode?
    @Published var errorMessage: String?

    private let scanner = DiskScanner()
    private let volumeDiscovery = VolumeDiscovery()
    private let fullDiskAccessChecker = FullDiskAccessChecker()
    private var scanSessionStore = ScanSessionStore()
    private var scanTask: Task<Void, Never>?
    private var activeScanID = UUID()
    private var volumeObserverTokens: [NSObjectProtocol] = []
    private var activationObserverToken: NSObjectProtocol?

    init() {
        refreshVolumes()
        observeVolumeChanges()
        observeApplicationActivation()
    }

    deinit {
        scanTask?.cancel()
        for token in volumeObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        if let activationObserverToken {
            NotificationCenter.default.removeObserver(activationObserverToken)
        }
    }

    var currentNode: FileNode? { navigationPath.last }
    var canNavigateBack: Bool { navigationPath.count > 1 }
    var isRequestingFullDiskAccess: Bool { pendingFullDiskScanURL != nil }

    func volumeForChart(node: FileNode) -> VolumeInfo? {
        guard result?.root.id == node.id else { return nil }
        let rootPath = node.url.standardizedFileURL.path
        return volumes.first { $0.url.standardizedFileURL.path == rootPath }
    }

    func refreshVolumes() {
        volumes = volumeDiscovery.mountedVolumes()
    }

    func selectVolume(_ volume: VolumeInfo) {
        if cachedResult(for: volume) != nil {
            pendingScanChoice = PendingScanChoice(volume: volume)
        } else {
            scan(volume.url)
        }
    }

    func selectSessionFolder(_ folder: SessionFolder) {
        if cachedResult(for: folder) != nil {
            pendingScanChoice = PendingScanChoice(folder: folder)
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
        pendingScanChoice = nil
        guard let cachedResult = cachedResult(at: url) else {
            scan(url)
            return
        }

        cancelScan()
        result = cachedResult
        navigationPath = [cachedResult.root]
        hoveredNode = nil
        errorMessage = nil
    }

    func dismissScanChoice() {
        pendingScanChoice = nil
    }

    func removeSessionFolder(_ folder: SessionFolder) {
        let folderPath = folder.url.standardizedFileURL.path
        sessionFolders.removeAll { $0.id == folder.id }
        scanSessionStore.removeResult(for: folder.url)

        if pendingScanChoice?.url.standardizedFileURL.path == folderPath {
            pendingScanChoice = nil
        }
        if scanningURL?.standardizedFileURL.path == folderPath {
            cancelScan()
        }
        if result?.root.url.standardizedFileURL.path == folderPath {
            result = nil
            navigationPath = []
            hoveredNode = nil
        }
    }

    func showDiskList() {
        cancelScan()
        pendingFullDiskScanURL = nil
        pendingScanChoice = nil
        result = nil
        navigationPath = []
        hoveredNode = nil
        progress = ScanProgress()
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
        scan(folder.url)
    }

    func scan(_ url: URL) {
        pendingScanChoice = nil
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
        scanningURL = url
        scanStartedAt = Date()
        isScanning = true
        progress = ScanProgress(currentPath: url.path)
        errorMessage = nil
        hoveredNode = nil

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await scanner.scan(url: url) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeScanID == scanID else { return }
                        self.progress = progress
                    }
                }

                guard !Task.isCancelled, activeScanID == scanID else { return }
                self.result = result
                if volumes.contains(where: {
                    $0.url.standardizedFileURL.path == url.standardizedFileURL.path
                }) || sessionFolders.contains(where: {
                    $0.url.standardizedFileURL.path == url.standardizedFileURL.path
                }) {
                    scanSessionStore.store(result, for: url)
                }
                navigationPath = [result.root]
                isScanning = false
                scanningURL = nil
                scanStartedAt = nil
                scanTask = nil
            } catch {
                guard activeScanID == scanID else { return }
                isScanning = false
                scanningURL = nil
                scanStartedAt = nil
                scanTask = nil
                if error is CancellationError { return }
                if let failure = error as? ScanFailure, case .cancelled = failure {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelScan() {
        activeScanID = UUID()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanningURL = nil
        scanStartedAt = nil
    }

    func rescan() {
        guard let rootURL = result?.root.url ?? scanningURL else { return }
        scan(rootURL)
    }

    func navigate(into node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        navigationPath.append(node)
        hoveredNode = nil
    }

    func navigate(toBreadcrumbAt index: Int) {
        guard navigationPath.indices.contains(index) else { return }
        navigationPath = Array(navigationPath.prefix(index + 1))
        hoveredNode = nil
    }

    func navigateBack() {
        guard canNavigateBack else { return }
        navigationPath.removeLast()
        hoveredNode = nil
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
}
