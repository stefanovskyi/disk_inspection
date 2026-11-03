import Foundation
import XCTest
@testable import SpaceLens

@MainActor
final class ScanCoordinatorTests: XCTestCase {
    func testRunsUpToTheLimitThenStartsQueuedWorkInOrder() {
        let coordinator = ScanCoordinator(maximumConcurrentActivities: 2)
        let ids = [UUID(), UUID(), UUID(), UUID()]
        var started: [Int] = []

        coordinator.enqueue(.storage, id: ids[0]) { started.append(0) }
        coordinator.enqueue(.aiCodingTools, id: ids[1]) { started.append(1) }
        coordinator.enqueue(.storage, id: ids[2]) { started.append(2) }
        coordinator.enqueue(.scanEverything, id: ids[3]) { started.append(3) }

        XCTAssertEqual(started, [0, 1])
        XCTAssertEqual(coordinator.queuedActivities, [.storage, .scanEverything])

        coordinator.finish(.aiCodingTools, id: ids[1])
        XCTAssertEqual(started, [0, 1, 2])
        coordinator.finish(.storage, id: ids[0])
        XCTAssertEqual(started, [0, 1, 2, 3])
    }

    func testFinishingQueuedWorkNeverStartsItAndStaleFinishIsIgnored() {
        let coordinator = ScanCoordinator(maximumConcurrentActivities: 1)
        let runningID = UUID()
        let queuedID = UUID()
        var queuedStarted = false

        coordinator.enqueue(.storage, id: runningID) {}
        coordinator.enqueue(.aiCodingTools, id: queuedID) { queuedStarted = true }

        coordinator.finish(.aiCodingTools, id: UUID())
        XCTAssertEqual(coordinator.queuedActivities, [.aiCodingTools])

        coordinator.finish(.aiCodingTools, id: queuedID)
        coordinator.finish(.storage, id: runningID)
        XCTAssertFalse(queuedStarted)
        XCTAssertTrue(coordinator.runningActivities.isEmpty)
    }
}

@MainActor
final class AppViewModelScanQueueTests: XCTestCase {
    private var fixtureRoot: URL!
    private var folderA: URL!
    private var folderB: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensQueueTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        folderA = fixtureRoot.appendingPathComponent("a", isDirectory: true)
        folderB = fixtureRoot.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: fixtureRoot)
    }

    private func makeModel(
        scanner: GatedScanner = GatedScanner(),
        maximumConcurrentActivities: Int = 2
    ) -> AppViewModel {
        AppViewModel(
            scanner: scanner,
            aiCodingToolsAnalyzer: GatedAICodingToolsAnalyzer(),
            fullDiskAccessChecker: FullDiskAccessChecker(accessProbe: { true }),
            maximumConcurrentActivities: maximumConcurrentActivities
        )
    }

    func testAnalysisKeepsRunningWhenNavigatingBetweenPages() {
        let model = makeModel()

        model.analyzeAICodingTools()
        XCTAssertTrue(model.aiCodingTools.isRunning)

        model.showAIModelsAndRuntimes()
        model.showDeveloperStorage()
        model.showDiskList()

        XCTAssertTrue(model.aiCodingTools.isRunning)
        XCTAssertEqual(model.activities.map(\.target), [.analysis(.aiCodingTools)])
        model.cancel(model.activities[0])
        XCTAssertFalse(model.aiCodingTools.isRunning)
    }

    func testBackAcrossPagesDoesNotCancelAnalysis() {
        let model = makeModel()
        model.analyzeAICodingTools()
        model.showAIModelsAndRuntimes()
        model.showDeveloperStorage()

        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .aiModelsAndRuntimes)
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .aiCodingTools)
        XCTAssertTrue(model.aiCodingTools.isRunning)
        XCTAssertEqual(model.activities.map(\.target), [.analysis(.aiCodingTools)])
        model.activities.forEach(model.cancel)
    }

    func testStorageScanKeepsRunningAcrossNavigationAndCachesItsResult() async throws {
        let scanner = GatedScanner()
        let model = makeModel(scanner: scanner)
        let folder = SessionFolder(url: folderA)

        model.inspectDeveloperStorageDirectory(folderA)
        XCTAssertTrue(model.isScanning)
        model.showAICodingTools()
        model.showDiskList()

        XCTAssertFalse(model.isScanning)
        XCTAssertTrue(model.isScanActive(at: folderA))

        await scanner.release(folderA)
        try await waitUntil { [folderA] in !model.isScanActive(at: folderA!) }

        XCTAssertNotNil(model.cachedResult(for: folder))
        XCTAssertNotEqual(model.result?.root.url.path, folderA.path)
    }

    func testScanAndAnalysisRunInParallelAndNeitherCancelsTheOther() {
        let model = makeModel()

        model.inspectDeveloperStorageDirectory(folderA)
        model.analyzeAICodingTools()

        XCTAssertTrue(model.isScanActive(at: folderA))
        XCTAssertTrue(model.aiCodingTools.isRunning)
        XCTAssertEqual(model.activities.count, 2)
        XCTAssertFalse(model.activities.contains(where: \.isQueued))
        model.activities.forEach(model.cancel)
        XCTAssertTrue(model.activities.isEmpty)
    }

    func testWorkBeyondTheLimitQueuesAndStartsWhenASlotOpens() async throws {
        let scanner = GatedScanner()
        let model = makeModel(scanner: scanner, maximumConcurrentActivities: 1)

        model.inspectDeveloperStorageDirectory(folderA)
        model.inspectDeveloperStorageDirectory(folderB)

        XCTAssertEqual(
            model.activities.map(\.isQueued),
            [false, true],
            "Running work should be listed first"
        )
        XCTAssertEqual(model.activities[1].status, ScanActivity.waitingStatus)
        XCTAssertEqual(model.presentedScan?.url, folderB)

        await scanner.release(folderA)
        try await waitUntil { [folderA] in !model.isScanActive(at: folderA!) }
        XCTAssertEqual(model.activities.map(\.isQueued), [false])

        await scanner.release(folderB)
        try await waitUntil { [folderB] in !model.isScanActive(at: folderB!) }
        XCTAssertEqual(model.result?.root.url.path, folderB.path)
        XCTAssertFalse(model.isScanning)
    }

    func testRequestingAnActiveScanAgainFollowsItInsteadOfRestarting() async throws {
        let scanner = GatedScanner()
        let model = makeModel(scanner: scanner)

        model.inspectDeveloperStorageDirectory(folderA)
        let job = try XCTUnwrap(model.presentedScan)
        model.inspectDeveloperStorageDirectory(folderB)
        model.inspectDeveloperStorageDirectory(folderA)

        XCTAssertTrue(model.presentedScan === job)
        XCTAssertEqual(model.activities.count, 2)
        model.activities.forEach(model.cancel)
    }

    func testBackgroundCompletionDoesNotReplaceTheVisibleLocation() async throws {
        let scanner = GatedScanner()
        let model = makeModel(scanner: scanner)

        model.inspectDeveloperStorageDirectory(folderA)
        model.inspectDeveloperStorageDirectory(folderB)
        await scanner.release(folderB)
        try await waitUntil { [folderB] in !model.isScanActive(at: folderB!) }
        XCTAssertEqual(model.result?.root.url.path, folderB.path)

        await scanner.release(folderA)
        try await waitUntil { [folderA] in !model.isScanActive(at: folderA!) }
        XCTAssertEqual(model.result?.root.url.path, folderB.path)
        XCTAssertNotNil(model.cachedResult(at: folderA))
    }

    func testCancellingOneActivityLeavesTheOthersRunning() throws {
        let model = makeModel()

        model.inspectDeveloperStorageDirectory(folderA)
        model.inspectDeveloperStorageDirectory(folderB)
        let path = folderA.standardizedFileURL.path
        let first = try XCTUnwrap(model.activities.first { $0.target == .storage(path: path) })
        model.cancel(first)

        XCTAssertFalse(model.isScanActive(at: folderA))
        XCTAssertTrue(model.isScanActive(at: folderB))
        XCTAssertEqual(model.presentedScan?.url, folderB)
        model.activities.forEach(model.cancel)
    }

    func testRefreshingExistingResultsIsReportedForTheFactsPage() async throws {
        let scanner = GatedScanner()
        let model = makeModel(scanner: scanner)

        model.inspectDeveloperStorageDirectory(folderA)
        XCTAssertNil(model.storageRefreshSource, "A first scan has no results to cover")

        await scanner.release(folderA)
        try await waitUntil { [folderA] in !model.isScanActive(at: folderA!) }
        XCTAssertNil(model.storageRefreshSource)

        await scanner.hold(folderA)
        model.rescan()
        XCTAssertEqual(model.storageRefreshSource, .presentedScan)
        XCTAssertNotNil(model.result)
        XCTAssertNotNil(model.startedAt(for: .presentedScan))

        model.activities.forEach(model.cancel)
        XCTAssertNil(model.storageRefreshSource)
        XCTAssertNotNil(model.result)
    }

    func testAnalysisStartTimeIsAvailableWithoutReadingProgress() {
        let model = makeModel()
        XCTAssertNil(model.startedAt(for: .analysis(.aiCodingTools)))

        model.analyzeAICodingTools()
        XCTAssertNotNil(model.startedAt(for: .analysis(.aiCodingTools)))
        model.activities.forEach(model.cancel)
    }

    func testAnalysisBatchSkipsAnalysisAlreadyRunning() {
        let model = makeModel()

        model.analyzeAICodingTools()
        model.requestAllAnalyses()

        XCTAssertEqual(
            model.pendingScanEverythingPlan?.analyses,
            [.aiModelsAndRuntimes, .developerStorage]
        )
        model.cancelScanEverythingConfirmation()
        model.activities.forEach(model.cancel)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for scan queue state")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

/// Holds every scan until the test releases its path; cancellation ends it early.
private actor ScanGate {
    private var released: Set<String> = []

    func release(_ path: String) { released.insert(path) }
    func hold(_ path: String) { released.remove(path) }
    func isReleased(_ path: String) -> Bool { released.contains(path) }
}

private struct GatedScanner: VolumeScanning {
    private let gate = ScanGate()

    func release(_ url: URL) async {
        await gate.release(url.standardizedFileURL.path)
    }

    func hold(_ url: URL) async {
        await gate.hold(url.standardizedFileURL.path)
    }

    func scan(
        url: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        while await !gate.isReleased(url.standardizedFileURL.path) {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let root = FileNode(
            url: url,
            name: url.lastPathComponent,
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: [],
            itemCount: 1
        )
        return ScanResult(root: root, duration: 0, itemsScanned: 1, unreadableItems: 0)
    }
}

private struct GatedAICodingToolsAnalyzer: AICodingToolsAnalyzing {
    func analyze(
        request: AICodingToolsRequest,
        onProgress: @escaping @Sendable (AICodingToolsProgress) -> Void
    ) async throws -> AICodingToolsReport {
        try await Task.sleep(nanoseconds: 30_000_000_000)
        throw CancellationError()
    }
}
