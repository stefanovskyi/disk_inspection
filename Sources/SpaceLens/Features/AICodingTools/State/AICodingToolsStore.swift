import Foundation
import Observation

struct AICodingProjectRoot: Identifiable, Equatable, Sendable {
    let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}

@MainActor
@Observable
final class AICodingToolsStore {
    typealias RequestFactory = ([URL]) -> AICodingToolsRequest

    private(set) var state: AICodingToolsAnalysisState = .idle
    private(set) var progress = AICodingToolsProgress()
    private(set) var startedAt: Date?
    private(set) var projectRoots: [AICodingProjectRoot] = []
    private(set) var selectedToolID: AICodingToolID?

    @ObservationIgnored private let analyzer: any AICodingToolsAnalyzing
    @ObservationIgnored private let scanCoordinator: ScanCoordinator
    @ObservationIgnored private let requestFactory: RequestFactory
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var activeAnalysisID: UUID?

    init(
        analyzer: any AICodingToolsAnalyzing = AICodingToolsAnalyzer(),
        scanCoordinator: ScanCoordinator,
        requestFactory: @escaping RequestFactory = { .currentUser(projectRoots: $0) }
    ) {
        self.analyzer = analyzer
        self.scanCoordinator = scanCoordinator
        self.requestFactory = requestFactory
    }

    deinit {
        task?.cancel()
    }

    var isRunning: Bool { state.isRunning }

    func selectTool(_ id: AICodingToolID) {
        selectedToolID = id
    }

    func addProjectRoot(_ url: URL) {
        let root = AICodingProjectRoot(url: url)
        if !projectRoots.contains(root) {
            projectRoots.append(root)
        }
        analyze()
    }

    func removeProjectRoot(_ root: AICodingProjectRoot) {
        projectRoots.removeAll { $0.id == root.id }
        if state.isRunning || state.report != nil {
            analyze()
        }
    }

    func analyze() {
        let previousReport = state.report
        let analysisID = UUID()
        scanCoordinator.begin(.aiCodingTools, id: analysisID) { [weak self] in
            self?.cancelPreservingReport(expectedID: analysisID)
        }

        activeAnalysisID = analysisID
        state = .running(previousReport: previousReport)
        progress = AICodingToolsProgress()
        startedAt = Date()

        let analyzer = analyzer
        let request = requestFactory(projectRoots.map(\.url))
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
                guard !Task.isCancelled,
                      activeAnalysisID == analysisID else { return }
                state = .completed(report)
                progress = AICodingToolsProgress()
                startedAt = nil
                task = nil
                activeAnalysisID = nil
                if selectedToolID == nil
                    || !report.tools.contains(where: { $0.id == self.selectedToolID }) {
                    selectedToolID = report.rankedTools.first?.id
                }
                scanCoordinator.finish(.aiCodingTools, id: analysisID)
            } catch {
                guard activeAnalysisID == analysisID else { return }
                task = nil
                progress = AICodingToolsProgress()
                startedAt = nil
                activeAnalysisID = nil
                scanCoordinator.finish(.aiCodingTools, id: analysisID)
                if error is CancellationError { return }
                if let failure = error as? ScanFailure, case .cancelled = failure { return }
                state = .failed(
                    message: error.localizedDescription,
                    previousReport: previousReport
                )
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
        progress = AICodingToolsProgress()
        startedAt = nil
        activeAnalysisID = nil
        state = report.map(AICodingToolsAnalysisState.completed) ?? .idle
        scanCoordinator.finish(.aiCodingTools, id: expectedID)
    }
}
