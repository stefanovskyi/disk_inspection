import Foundation
import XCTest
@testable import SpaceLens

@MainActor
final class AICodingToolsStoreTests: XCTestCase {
    func testStorePublishesProgressCompletesAndSelectsFirstRankedTool() async throws {
        let report = makeReport(tool: .cursor, size: 64)
        let store = AICodingToolsStore(
            analyzer: ImmediateAICodingToolsAnalyzer(report: report),
            scanCoordinator: ScanCoordinator(),
            requestFactory: fixtureRequest
        )

        store.analyze()
        try await waitUntil { !store.isRunning }

        XCTAssertEqual(store.state.report, report)
        XCTAssertEqual(store.selectedToolID, .cursor)
        XCTAssertNil(store.startedAt)
    }

    func testOtherActivitiesLeaveRefreshRunningAndCancelRestoresReport() async throws {
        let report = makeReport(tool: .codex, size: 128)
        let sequence = SequencedAICodingToolsAnalyzer(report: report)
        let coordinator = ScanCoordinator()
        let store = AICodingToolsStore(
            analyzer: sequence,
            scanCoordinator: coordinator,
            requestFactory: fixtureRequest
        )

        store.analyze()
        try await waitUntil { !store.isRunning }
        store.analyze()
        try await waitUntil { store.isRunning }
        let storageID = UUID()
        coordinator.enqueue(.storage, id: storageID) {}

        XCTAssertTrue(store.isRunning)
        XCTAssertEqual(coordinator.runningActivities, [.aiCodingTools, .storage])

        store.cancelPreservingReport()
        XCTAssertFalse(store.isRunning)
        XCTAssertEqual(store.state.report, report)
        XCTAssertNil(store.startedAt)
        XCTAssertEqual(coordinator.runningActivities, [.storage])
        coordinator.finish(.storage, id: storageID)
    }

    func testStoreWaitsForAFreeSlotThenStarts() async throws {
        let report = makeReport(tool: .cursor, size: 64)
        let coordinator = ScanCoordinator(maximumConcurrentActivities: 1)
        let store = AICodingToolsStore(
            analyzer: ImmediateAICodingToolsAnalyzer(report: report),
            scanCoordinator: coordinator,
            requestFactory: fixtureRequest
        )
        let storageID = UUID()
        coordinator.enqueue(.storage, id: storageID) {}

        store.analyze()
        XCTAssertTrue(store.isQueued)
        XCTAssertNil(store.startedAt)

        coordinator.finish(.storage, id: storageID)
        try await waitUntil { !store.isRunning }
        XCTAssertEqual(store.state.report, report)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for AI coding tools state")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func fixtureRequest(projectRoots: [URL]) -> AICodingToolsRequest {
        let root = URL(fileURLWithPath: "/tmp/SpaceLensStoreTests", isDirectory: true)
        return AICodingToolsRequest(
            homeDirectory: root,
            applicationSupportDirectory: root,
            environment: [:],
            projectRoots: projectRoots
        )
    }

    private func makeReport(tool: AICodingToolID, size: Int64) -> AICodingToolsReport {
        let rootURL = URL(fileURLWithPath: "/tmp/SpaceLensStoreTests/\(tool.rawValue)")
        let root = FileNode(
            url: rootURL,
            name: tool.rawValue,
            size: size,
            isDirectory: true,
            isReadable: true,
            children: [],
            itemCount: 1
        )
        let location = AICodingStorageLocation(
            toolID: tool,
            name: tool.rawValue,
            url: rootURL,
            explanation: "Test fixture",
            status: .measured,
            root: root,
            categories: [],
            defaultCategory: .other,
            rules: []
        )
        return AICodingToolsReport(
            tools: [
                AICodingToolReport(
                    tool: AICodingToolsCatalog.metadata(for: tool),
                    locations: [location]
                )
            ],
            startedAt: Date(timeIntervalSince1970: 1),
            duration: 0.25
        )
    }
}

private struct ImmediateAICodingToolsAnalyzer: AICodingToolsAnalyzing {
    let report: AICodingToolsReport

    func analyze(
        request: AICodingToolsRequest,
        onProgress: @escaping @Sendable (AICodingToolsProgress) -> Void
    ) async throws -> AICodingToolsReport {
        onProgress(AICodingToolsProgress(itemsScanned: 1, mappedBytes: report.totalSize))
        return report
    }
}

private actor SequencedAICodingToolsAnalyzer: AICodingToolsAnalyzing {
    let report: AICodingToolsReport
    private var callCount = 0

    init(report: AICodingToolsReport) {
        self.report = report
    }

    func analyze(
        request: AICodingToolsRequest,
        onProgress: @escaping @Sendable (AICodingToolsProgress) -> Void
    ) async throws -> AICodingToolsReport {
        callCount += 1
        if callCount == 1 { return report }
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return report
    }
}
