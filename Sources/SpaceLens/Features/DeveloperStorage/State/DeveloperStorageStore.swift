import Foundation
import Observation

struct DeveloperProjectContainer: Identifiable, Equatable, Sendable {
    let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

@MainActor
@Observable
final class DeveloperStorageStore {
    typealias RequestFactory = ([URL]) -> DeveloperStorageRequest

    private(set) var state: DeveloperStorageAnalysisState = .idle
    private(set) var progress = DeveloperStorageProgress()
    private(set) var startedAt: Date?
    private(set) var projectContainers: [DeveloperProjectContainer] = []
    private(set) var selectedEcosystemID: DeveloperEcosystemID?

    @ObservationIgnored private let analyzer: any DeveloperStorageAnalyzing
    @ObservationIgnored private let scanCoordinator: ScanCoordinator
    @ObservationIgnored private let requestFactory: RequestFactory
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activeAnalysisID: UUID?

    init(
        analyzer: any DeveloperStorageAnalyzing = DeveloperStorageAnalyzer(),
        scanCoordinator: ScanCoordinator,
        requestFactory: @escaping RequestFactory = { .currentUser(projectContainers: $0) }
    ) {
        self.analyzer = analyzer
        self.scanCoordinator = scanCoordinator
        self.requestFactory = requestFactory
    }

    deinit { task?.cancel() }

    var isRunning: Bool { state.isRunning }

    func selectEcosystem(_ id: DeveloperEcosystemID) {
        selectedEcosystemID = id
    }

    func addProjectContainer(_ url: URL) {
        let container = DeveloperProjectContainer(url: url)
        if !projectContainers.contains(container) {
            projectContainers.append(container)
        }
        if state.report != nil { analyze() }
    }

    func removeProjectContainer(_ container: DeveloperProjectContainer) {
        projectContainers.removeAll { $0.id == container.id }
        if state.isRunning || state.report != nil { analyze() }
    }

    func analyze() {
        let previousReport = state.report
        let analysisID = UUID()
        scanCoordinator.begin(.developerStorage, id: analysisID) { [weak self] in
            self?.cancelPreservingReport(expectedID: analysisID)
        }
        activeAnalysisID = analysisID
        state = .running(previousReport: previousReport)
        progress = DeveloperStorageProgress()
        startedAt = Date()

        let analyzer = analyzer
        let request = requestFactory(projectContainers.map(\.url))
        task = Task { [weak self] in
            guard let self else { return }
            let progressStore = self
            do {
                let report = try await analyzer.analyze(request: request) { progress in
                    Task { @MainActor in
                        guard progressStore.activeAnalysisID == analysisID,
                              progressStore.state.isRunning else { return }
                        progressStore.progress = progress
                    }
                }
                guard !Task.isCancelled, activeAnalysisID == analysisID else { return }
                state = .completed(report)
                progress = DeveloperStorageProgress()
                startedAt = nil
                task = nil
                activeAnalysisID = nil
                if selectedEcosystemID == nil
                    || !report.ecosystems.contains(where: { $0.id == self.selectedEcosystemID }) {
                    selectedEcosystemID = report.rankedEcosystems.first?.id
                }
                scanCoordinator.finish(.developerStorage, id: analysisID)
            } catch {
                guard activeAnalysisID == analysisID else { return }
                task = nil
                progress = DeveloperStorageProgress()
                startedAt = nil
                activeAnalysisID = nil
                scanCoordinator.finish(.developerStorage, id: analysisID)
                if error is CancellationError { return }
                if let failure = error as? ScanFailure, case .cancelled = failure { return }
                state = .failed(message: error.localizedDescription, previousReport: previousReport)
            }
        }
    }

    func cancelPreservingReport() {
        guard let activeAnalysisID else { return }
        cancelPreservingReport(expectedID: activeAnalysisID)
    }

    private func cancelPreservingReport(expectedID: UUID) {
        guard activeAnalysisID == expectedID else { return }
        let report = state.report
        task?.cancel()
        task = nil
        progress = DeveloperStorageProgress()
        startedAt = nil
        activeAnalysisID = nil
        state = report.map(DeveloperStorageAnalysisState.completed) ?? .idle
        scanCoordinator.finish(.developerStorage, id: expectedID)
    }
}
