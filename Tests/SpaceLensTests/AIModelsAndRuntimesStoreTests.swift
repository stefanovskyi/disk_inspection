import Foundation
import XCTest
@testable import SpaceLens

@MainActor
final class AIModelsAndRuntimesStoreTests: XCTestCase {
    func testStorePublishesReportAndSelectsLargestRuntime() async throws {
        let report = makeReport(runtimeID: .lmStudio, size: 4_096)
        let store = AIModelsAndRuntimesStore(
            analyzer: ImmediateAIModelsAnalyzer(report: report),
            scanCoordinator: ScanCoordinator(),
            requestFactory: fixtureRequest
        )

        store.analyze()
        try await waitUntil { !store.isRunning }

        XCTAssertEqual(store.state.report, report)
        XCTAssertEqual(store.selectedRuntimeID, .lmStudio)
        XCTAssertNil(store.startedAt)
    }

    func testStartingStorageScanCancelsRefreshAndPreservesPreviousReport() async throws {
        let report = makeReport(runtimeID: .ollama, size: 8_192)
        let analyzer = SequencedAIModelsAnalyzer(report: report)
        let coordinator = ScanCoordinator()
        let store = AIModelsAndRuntimesStore(
            analyzer: analyzer,
            scanCoordinator: coordinator,
            requestFactory: fixtureRequest
        )

        store.analyze()
        try await waitUntil { !store.isRunning }
        store.analyze()
        try await waitUntil { store.isRunning }

        let storageID = UUID()
        coordinator.begin(.storage, id: storageID) {}

        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.state.report, report)
        XCTAssertEqual(coordinator.activeActivity, .storage)
        coordinator.finish(.storage, id: storageID)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for AI model analysis state")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func fixtureRequest(additionalRoots: [URL]) -> AIModelsAndRuntimesRequest {
        let root = URL(fileURLWithPath: "/tmp/SpaceLensAIModelsStoreTests", isDirectory: true)
        return AIModelsAndRuntimesRequest(
            homeDirectory: root,
            applicationSupportDirectory: root,
            environment: [:],
            additionalModelRoots: additionalRoots
        )
    }

    private func makeReport(
        runtimeID: AIModelRuntimeID,
        size: Int64
    ) -> AIModelsAndRuntimesReport {
        let metadata = AIModelsCatalog.metadata(for: runtimeID)
        let url = URL(fileURLWithPath: "/tmp/SpaceLensAIModelsStoreTests/\(runtimeID.rawValue)")
        let root = FileNode(
            url: url,
            name: runtimeID.rawValue,
            size: size,
            isDirectory: true,
            isReadable: true,
            children: [],
            itemCount: 1
        )
        let location = AIModelStorageLocation(
            runtimeID: runtimeID,
            name: metadata.displayName,
            url: url,
            size: size,
            itemCount: 1,
            latestModificationDate: nil,
            status: .measured,
            root: root
        )
        return AIModelsAndRuntimesReport(
            runtimes: [
                AIModelRuntimeReport(
                    runtime: metadata,
                    models: [],
                    installations: [],
                    locations: [location],
                    categories: []
                )
            ],
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2)
        )
    }
}

private struct ImmediateAIModelsAnalyzer: AIModelsAndRuntimesAnalyzing {
    let report: AIModelsAndRuntimesReport

    func analyze(
        request: AIModelsAndRuntimesRequest,
        onProgress: @escaping @Sendable (AIModelsProgress) -> Void
    ) async throws -> AIModelsAndRuntimesReport {
        onProgress(AIModelsProgress(itemsScanned: 1, mappedBytes: report.totalSize))
        return report
    }
}

private actor SequencedAIModelsAnalyzer: AIModelsAndRuntimesAnalyzing {
    let report: AIModelsAndRuntimesReport
    private var callCount = 0

    init(report: AIModelsAndRuntimesReport) {
        self.report = report
    }

    func analyze(
        request: AIModelsAndRuntimesRequest,
        onProgress: @escaping @Sendable (AIModelsProgress) -> Void
    ) async throws -> AIModelsAndRuntimesReport {
        callCount += 1
        if callCount == 1 { return report }
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return report
    }
}
