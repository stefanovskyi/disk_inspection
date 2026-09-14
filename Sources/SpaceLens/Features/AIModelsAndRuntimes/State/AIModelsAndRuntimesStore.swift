import Foundation
import Observation

struct AIModelsAdditionalRoot: Identifiable, Equatable, Sendable {
    let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

@MainActor
@Observable
final class AIModelsAndRuntimesStore {
    typealias RequestFactory = ([URL]) -> AIModelsAndRuntimesRequest

    private(set) var state: AIModelsAnalysisState = .idle
    private(set) var progress = AIModelsProgress()
    private(set) var startedAt: Date?
    private(set) var additionalRoots: [AIModelsAdditionalRoot] = []
    private(set) var selectedRuntimeID: AIModelRuntimeID?

    @ObservationIgnored private let analyzer: any AIModelsAndRuntimesAnalyzing
    @ObservationIgnored private let scanCoordinator: ScanCoordinator
    @ObservationIgnored private let requestFactory: RequestFactory
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activeAnalysisID: UUID?

    init(
        analyzer: any AIModelsAndRuntimesAnalyzing = AIModelsAndRuntimesAnalyzer(),
        scanCoordinator: ScanCoordinator,
        requestFactory: @escaping RequestFactory = { .currentUser(additionalModelRoots: $0) }
    ) {
        self.analyzer = analyzer
        self.scanCoordinator = scanCoordinator
        self.requestFactory = requestFactory
    }

    deinit {
        task?.cancel()
    }

    var isRunning: Bool { state.isRunning }

    func selectRuntime(_ id: AIModelRuntimeID) {
        selectedRuntimeID = id
    }

    func installReport(_ report: AIModelsAndRuntimesReport) {
        if activeAnalysisID != nil { cancelPreservingReport() }
        state = .completed(report)
        progress = AIModelsProgress()
        startedAt = nil
        if selectedRuntimeID == nil
            || !report.runtimes.contains(where: { $0.id == selectedRuntimeID }) {
            selectedRuntimeID = report.rankedRuntimes.first?.id
        }
    }

    func addRoot(_ url: URL) {
        let root = AIModelsAdditionalRoot(url: url)
        if !additionalRoots.contains(root) {
            additionalRoots.append(root)
        }
    }

    func removeRoot(_ root: AIModelsAdditionalRoot) {
        additionalRoots.removeAll { $0.id == root.id }
    }

    func analyze() {
        let previousReport = state.report
        let analysisID = UUID()
        scanCoordinator.begin(.aiModelsAndRuntimes, id: analysisID) { [weak self] in
            self?.cancelPreservingReport(expectedID: analysisID)
        }
        activeAnalysisID = analysisID
        state = .running(previousReport: previousReport)
        progress = AIModelsProgress()
        startedAt = Date()

        let analyzer = analyzer
        let request = requestFactory(additionalRoots.map(\.url))
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
                progress = AIModelsProgress()
                startedAt = nil
                task = nil
                activeAnalysisID = nil
                if selectedRuntimeID == nil
                    || !report.runtimes.contains(where: { $0.id == self.selectedRuntimeID }) {
                    selectedRuntimeID = report.rankedRuntimes.first?.id
                }
                scanCoordinator.finish(.aiModelsAndRuntimes, id: analysisID)
            } catch {
                guard activeAnalysisID == analysisID else { return }
                task = nil
                progress = AIModelsProgress()
                startedAt = nil
                activeAnalysisID = nil
                scanCoordinator.finish(.aiModelsAndRuntimes, id: analysisID)
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
        progress = AIModelsProgress()
        startedAt = nil
        activeAnalysisID = nil
        state = report.map(AIModelsAnalysisState.completed) ?? .idle
        scanCoordinator.finish(.aiModelsAndRuntimes, id: expectedID)
    }
}
