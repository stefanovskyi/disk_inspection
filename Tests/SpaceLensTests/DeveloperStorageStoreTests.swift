import Foundation
import XCTest
@testable import SpaceLens

@MainActor
final class DeveloperStorageStoreTests: XCTestCase {
    func testStoreCompletesAndSelectsLargestEcosystem() async throws {
        let report = makeReport(ecosystem: .python, size: 4_096)
        let store = DeveloperStorageStore(
            analyzer: ImmediateDeveloperStorageAnalyzer(report: report),
            scanCoordinator: ScanCoordinator(),
            requestFactory: fixtureRequest
        )

        store.analyze()
        try await waitUntil { !store.isRunning }

        XCTAssertEqual(store.state.report, report)
        XCTAssertEqual(store.selectedEcosystemID, .python)
        XCTAssertNil(store.startedAt)
    }

    func testReplacementScanCancelsAnalysisAndPreservesPreviousReport() async throws {
        let report = makeReport(ecosystem: .javaAndJVM, size: 8_192)
        let coordinator = ScanCoordinator()
        let store = DeveloperStorageStore(
            analyzer: SequencedDeveloperStorageAnalyzer(report: report),
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
                XCTFail("Timed out waiting for Developer Storage state")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func fixtureRequest(projectContainers: [URL]) -> DeveloperStorageRequest {
        DeveloperStorageRequest(
            homeDirectory: URL(fileURLWithPath: "/tmp/SpaceLensDeveloperStoreTests", isDirectory: true),
            environment: [:],
            projectContainers: projectContainers
        )
    }

    private func makeReport(
        ecosystem: DeveloperEcosystemID,
        size: Int64
    ) -> DeveloperStorageReport {
        let url = URL(fileURLWithPath: "/tmp/SpaceLensDeveloperStoreTests/\(ecosystem.rawValue)")
        let root = FileNode(
            url: url,
            name: ecosystem.rawValue,
            size: size,
            isDirectory: true,
            isReadable: true,
            children: [],
            itemCount: 1
        )
        let breakdown = DeveloperStorageBreakdown(
            kind: .toolchains,
            uniqueSize: size,
            referencedSize: size,
            itemCount: 1
        )
        let location = DeveloperStorageLocation(
            ecosystemID: ecosystem,
            scope: .shared,
            kind: .toolchains,
            name: ecosystem.displayName,
            url: url,
            projectURL: nil,
            uniqueSize: size,
            referencedSize: size,
            itemCount: 1,
            latestModificationDate: nil,
            status: .measured,
            root: root,
            breakdowns: [breakdown]
        )
        return DeveloperStorageReport(
            ecosystems: [DeveloperEcosystemReport(ecosystemID: ecosystem, locations: [location])],
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2)
        )
    }
}

private struct ImmediateDeveloperStorageAnalyzer: DeveloperStorageAnalyzing {
    let report: DeveloperStorageReport

    func analyze(
        request: DeveloperStorageRequest,
        onProgress: @escaping @Sendable (DeveloperStorageProgress) -> Void
    ) async throws -> DeveloperStorageReport {
        onProgress(DeveloperStorageProgress(itemsScanned: 1, mappedBytes: report.totalSize))
        return report
    }
}

private actor SequencedDeveloperStorageAnalyzer: DeveloperStorageAnalyzing {
    let report: DeveloperStorageReport
    private var callCount = 0

    init(report: DeveloperStorageReport) {
        self.report = report
    }

    func analyze(
        request: DeveloperStorageRequest,
        onProgress: @escaping @Sendable (DeveloperStorageProgress) -> Void
    ) async throws -> DeveloperStorageReport {
        callCount += 1
        if callCount == 1 { return report }
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return report
    }
}
