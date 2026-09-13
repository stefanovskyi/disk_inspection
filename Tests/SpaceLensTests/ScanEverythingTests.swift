import Foundation
import XCTest
@testable import SpaceLens

final class ScanEverythingTests: XCTestCase {
    func testPlanUsesLocalVolumesOnceAndRunsEveryVolumeBeforeAnalyses() {
        let startup = volume(name: "Macintosh HD", path: "/", uuid: "startup")
        let internalArchive = volume(
            name: "Archive",
            path: "/Volumes/Archive",
            uuid: "archive"
        )
        let external = volume(
            name: "T7 Touch",
            path: "/Volumes/T7 Touch",
            uuid: "external",
            isExternal: true
        )
        let duplicateExternal = volume(
            name: "Duplicate mount",
            path: "/Volumes/T7 Duplicate",
            uuid: "external",
            isExternal: true
        )
        let network = volume(
            name: "Server",
            path: "/Volumes/Server",
            uuid: "network",
            isExternal: true,
            isLocal: false
        )

        let plan = ScanEverythingPlan(
            volumes: [external, network, internalArchive, duplicateExternal, startup]
        )

        XCTAssertEqual(plan.volumes, [startup, internalArchive, external])
        XCTAssertEqual(
            plan.steps,
            [
                .volume(startup),
                .volume(internalArchive),
                .volume(external),
                .analysis(.aiCodingTools),
                .analysis(.aiModelsAndRuntimes),
                .analysis(.developerStorage)
            ]
        )
        XCTAssertTrue(plan.includesStartupVolume)
    }

    func testUnknownDeviceFallbackIsConservativeForInternalVolumes() {
        let startup = volume(name: "Macintosh HD", path: "/", uuid: "startup")
        let data = volume(name: "Data", path: "/System/Volumes/Data", uuid: "data")
        let firstExternal = volume(
            name: "One",
            path: "/Volumes/One",
            uuid: "one",
            isExternal: true
        )
        let secondExternal = volume(
            name: "Two",
            path: "/Volumes/Two",
            uuid: "two",
            isExternal: true
        )

        XCTAssertEqual(startup.scanDeviceKey, data.scanDeviceKey)
        XCTAssertNotEqual(firstExternal.scanDeviceKey, secondExternal.scanDeviceKey)
    }

    func testDistinctPhysicalDevicesOverlap() async throws {
        let volumes = [
            volume(name: "One", path: "/Volumes/One", uuid: "one", physicalDevice: "disk1"),
            volume(name: "Two", path: "/Volumes/Two", uuid: "two", physicalDevice: "disk2")
        ]
        let scanner = TimedVolumeScanner(defaultDelay: 120_000_000)

        _ = try await runner(scanner: scanner).run(
            plan: ScanEverythingPlan(volumes: volumes, analyses: []),
            requests: currentUserRequests()
        )

        let maximumActiveScans = await scanner.maximumActiveScans
        XCTAssertEqual(maximumActiveScans, 2)
    }

    func testSamePhysicalDeviceNeverOverlaps() async throws {
        let volumes = [
            volume(name: "One", path: "/Volumes/One", uuid: "one", physicalDevice: "disk1"),
            volume(name: "Two", path: "/Volumes/Two", uuid: "two", physicalDevice: "disk1")
        ]
        let scanner = TimedVolumeScanner(defaultDelay: 40_000_000)

        _ = try await runner(scanner: scanner).run(
            plan: ScanEverythingPlan(volumes: volumes, analyses: []),
            requests: currentUserRequests()
        )

        let maximumActiveScans = await scanner.maximumActiveScans
        let startedPaths = await scanner.startedPaths
        XCTAssertEqual(maximumActiveScans, 1)
        XCTAssertEqual(Set(startedPaths), Set(volumes.map { $0.url.path }))
    }

    func testActiveVolumeScansNeverExceedPolicy() async throws {
        let volumes = (1...5).map {
            volume(
                name: "Disk \($0)",
                path: "/Volumes/Disk\($0)",
                uuid: "disk-\($0)",
                physicalDevice: "disk\($0)"
            )
        }
        let scanner = TimedVolumeScanner(defaultDelay: 50_000_000)
        let policy = ScanEverythingExecutionPolicy(
            maximumConcurrentVolumeScans: 2,
            maximumDirectoryReaders: 4,
            maximumScansPerPhysicalDevice: 1,
            progressUpdatesPerSecond: 10
        )

        _ = try await runner(scanner: scanner, policy: policy).run(
            plan: ScanEverythingPlan(volumes: volumes, analyses: []),
            requests: currentUserRequests()
        )

        let maximumActiveScans = await scanner.maximumActiveScans
        XCTAssertEqual(maximumActiveScans, 2)
    }

    func testFailedVolumeDoesNotCancelHealthySibling() async throws {
        let startup = volume(
            name: "Macintosh HD",
            path: "/",
            uuid: "startup",
            physicalDevice: "disk0"
        )
        let external = volume(
            name: "External",
            path: "/Volumes/External",
            uuid: "external",
            physicalDevice: "disk1"
        )
        let scanner = TimedVolumeScanner(
            defaultDelay: 30_000_000,
            failingPaths: ["/"]
        )

        let summary = try await runner(scanner: scanner).run(
            plan: ScanEverythingPlan(volumes: [external, startup], analyses: []),
            requests: currentUserRequests()
        )

        let startedPaths = await scanner.startedPaths
        XCTAssertEqual(Set(startedPaths), ["/", "/Volumes/External"])
        XCTAssertEqual(summary.outcomes.map(\.step), [.volume(startup), .volume(external)])
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.failureCount, 1)
    }

    func testCancellationStopsAllActiveVolumesAndDoesNotStartPendingWork() async throws {
        let volumes = (1...3).map {
            volume(
                name: "Disk \($0)",
                path: "/Volumes/Disk\($0)",
                uuid: "disk-\($0)",
                physicalDevice: "disk\($0)"
            )
        }
        let scanner = TimedVolumeScanner(defaultDelay: 30_000_000_000)
        let task = Task {
            try await runner(scanner: scanner).run(
                plan: ScanEverythingPlan(volumes: volumes, analyses: []),
                requests: currentUserRequests()
            )
        }
        await scanner.waitUntilStarted(count: 2)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled Scan Everything run completed successfully")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let startedPaths = await scanner.startedPaths
        let cancelledScanCount = await scanner.cancelledScanCount
        XCTAssertEqual(startedPaths.count, 2)
        XCTAssertEqual(cancelledScanCount, 2)
    }

    func testCompletionOrderDoesNotChangeSummaryOrder() async throws {
        let slow = volume(
            name: "A Slow",
            path: "/Volumes/Slow",
            uuid: "slow",
            physicalDevice: "disk1"
        )
        let fast = volume(
            name: "B Fast",
            path: "/Volumes/Fast",
            uuid: "fast",
            physicalDevice: "disk2"
        )
        let scanner = TimedVolumeScanner(
            defaultDelay: 10_000_000,
            delaysByPath: [slow.url.path: 150_000_000]
        )

        let summary = try await runner(scanner: scanner).run(
            plan: ScanEverythingPlan(volumes: [fast, slow], analyses: []),
            requests: currentUserRequests()
        )

        let finishedPaths = await scanner.finishedPaths
        XCTAssertEqual(finishedPaths.first, fast.url.path)
        XCTAssertEqual(summary.outcomes.map(\.step), [.volume(slow), .volume(fast)])
    }

    func testAnalysesStartAfterVolumesAndRemainSequential() async throws {
        let timeline = OperationTimeline()
        let volumes = [
            volume(name: "One", path: "/Volumes/One", uuid: "one", physicalDevice: "disk1"),
            volume(name: "Two", path: "/Volumes/Two", uuid: "two", physicalDevice: "disk2")
        ]
        let scanner = TimedVolumeScanner(defaultDelay: 60_000_000, timeline: timeline)
        let runner = ScanEverythingRunner(
            volumeScannerFactory: FixedVolumeScannerFactory(scanner: scanner),
            aiCodingToolsAnalyzer: FailingAICodingAnalyzer(timeline: timeline),
            aiModelsAndRuntimesAnalyzer: FailingAIModelsAnalyzer(timeline: timeline),
            developerStorageAnalyzer: FailingDeveloperStorageAnalyzer(timeline: timeline)
        )

        let summary = try await runner.run(
            plan: ScanEverythingPlan(volumes: volumes),
            requests: currentUserRequests()
        )
        let snapshot = await timeline.snapshot

        XCTAssertFalse(snapshot.analysisOverlappedVolume)
        XCTAssertEqual(snapshot.maximumActiveAnalyses, 1)
        XCTAssertEqual(snapshot.analysisOrder, ScanEverythingAnalysis.allCases.map(\.rawValue))
        XCTAssertEqual(summary.outcomes.map(\.step), ScanEverythingPlan(volumes: volumes).steps)
    }

    func testProgressShowsBothVolumesAndNeverMovesBackward() async throws {
        let volumes = [
            volume(name: "One", path: "/Volumes/One", uuid: "one", physicalDevice: "disk1"),
            volume(name: "Two", path: "/Volumes/Two", uuid: "two", physicalDevice: "disk2")
        ]
        let scanner = TimedVolumeScanner(defaultDelay: 80_000_000, emitsBurstProgress: true)
        let events = ProgressEventRecorder()

        _ = try await runner(scanner: scanner).run(
            plan: ScanEverythingPlan(volumes: volumes, analyses: []),
            requests: currentUserRequests(),
            onEvent: { event in await events.record(event) }
        )

        let snapshots = await events.progressSnapshots
        XCTAssertTrue(snapshots.contains { $0.activeVolumeCount == 2 })
        XCTAssertEqual(snapshots.last?.completedStepIDs.count, 2)
        XCTAssertEqual(snapshots.last?.overallFraction, 1)
        XCTAssertEqual(
            snapshots.map(\.overallFraction),
            snapshots.map(\.overallFraction).sorted()
        )
    }

    func testDefaultVolumeScannerUsesCountsOnlyProgress() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensEverythingCountsOnly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 4_096)
            .write(to: root.appendingPathComponent("payload.bin"))

        let recorder = VolumeProgressRecorder()
        let scanner = DefaultVolumeScannerFactory().makeScanner(
            traversalBudget: ScanTraversalBudget(permitCount: 1)
        )
        let result = try await scanner.scan(url: root) { recorder.record($0) }

        XCTAssertEqual(recorder.latest?.itemsScanned, result.itemsScanned)
        XCTAssertEqual(recorder.latest?.mappedBytes, result.root.size)
        XCTAssertTrue(recorder.snapshots.allSatisfy { $0.previewRoot == nil })
        XCTAssertEqual(result.diagnostics.previewConstructions, 0)
    }

    private func runner(
        scanner: any VolumeScanning,
        policy: ScanEverythingExecutionPolicy = .adaptive
    ) -> ScanEverythingRunner {
        ScanEverythingRunner(
            executionPolicy: policy,
            volumeScannerFactory: FixedVolumeScannerFactory(scanner: scanner)
        )
    }

    private func currentUserRequests() -> ScanEverythingRequests {
        ScanEverythingRequests(
            aiCodingTools: .currentUser(),
            aiModelsAndRuntimes: .currentUser(),
            developerStorage: .currentUser()
        )
    }

    private func volume(
        name: String,
        path: String,
        uuid: String,
        isExternal: Bool = false,
        isLocal: Bool = true,
        physicalDevice: String? = nil
    ) -> VolumeInfo {
        VolumeInfo(
            url: URL(fileURLWithPath: path, isDirectory: true),
            name: name,
            totalCapacity: 100,
            availableCapacity: 50,
            isExternal: isExternal,
            isReadOnly: false,
            uuid: uuid,
            isLocal: isLocal,
            physicalDeviceIdentifier: physicalDevice
        )
    }
}

private struct FixedVolumeScannerFactory: VolumeScannerFactory {
    let scanner: any VolumeScanning

    func makeScanner(traversalBudget: ScanTraversalBudget) -> any VolumeScanning {
        scanner
    }
}

private enum TestRunnerError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let path): "Failed \(path)"
        }
    }
}

private actor TimedVolumeScanner: VolumeScanning {
    private let defaultDelay: UInt64
    private let delaysByPath: [String: UInt64]
    private let failingPaths: Set<String>
    private let timeline: OperationTimeline?
    private let emitsBurstProgress: Bool
    private var activeScans = 0
    private(set) var maximumActiveScans = 0
    private(set) var startedPaths: [String] = []
    private(set) var finishedPaths: [String] = []
    private(set) var cancelledScanCount = 0

    init(
        defaultDelay: UInt64,
        delaysByPath: [String: UInt64] = [:],
        failingPaths: Set<String> = [],
        timeline: OperationTimeline? = nil,
        emitsBurstProgress: Bool = false
    ) {
        self.defaultDelay = defaultDelay
        self.delaysByPath = delaysByPath
        self.failingPaths = failingPaths
        self.timeline = timeline
        self.emitsBurstProgress = emitsBurstProgress
    }

    func waitUntilStarted(count: Int) async {
        while startedPaths.count < count {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func scan(
        url: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let path = url.standardizedFileURL.path
        startedPaths.append(path)
        activeScans += 1
        maximumActiveScans = max(maximumActiveScans, activeScans)
        if let timeline { await timeline.beginVolume() }

        do {
            let progressCount = emitsBurstProgress ? 100 : 1
            for item in 1...progressCount {
                onProgress(
                    ScanProgress(
                        currentPath: path,
                        itemsScanned: item,
                        mappedBytes: Int64(min(item, 50))
                    )
                )
            }
            try await Task.sleep(nanoseconds: delaysByPath[path] ?? defaultDelay)
            if failingPaths.contains(path) { throw TestRunnerError.failed(path) }
            activeScans -= 1
            finishedPaths.append(path)
            if let timeline { await timeline.endVolume() }
            return Self.result(for: url)
        } catch {
            activeScans -= 1
            if error is CancellationError { cancelledScanCount += 1 }
            if let timeline { await timeline.endVolume() }
            throw error
        }
    }

    private static func result(for url: URL) -> ScanResult {
        ScanResult(
            root: FileNode(
                url: url,
                name: url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent,
                size: 50,
                isDirectory: true,
                isReadable: true,
                children: []
            ),
            duration: 0,
            itemsScanned: 1,
            unreadableItems: 0
        )
    }
}

private actor ProgressEventRecorder {
    private(set) var progressSnapshots: [ScanEverythingProgress] = []

    func record(_ event: ScanEverythingEvent) {
        if case .progress(let progress) = event {
            progressSnapshots.append(progress)
        }
    }
}

private final class VolumeProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ScanProgress] = []

    var latest: ScanProgress? {
        lock.withLock { values.last }
    }

    var snapshots: [ScanProgress] {
        lock.withLock { values }
    }

    func record(_ progress: ScanProgress) {
        lock.withLock { values.append(progress) }
    }
}

private actor OperationTimeline {
    struct Snapshot: Sendable {
        let analysisOverlappedVolume: Bool
        let maximumActiveAnalyses: Int
        let analysisOrder: [String]
    }

    private var activeVolumes = 0
    private var activeAnalyses = 0
    private var analysisOverlappedVolume = false
    private var maximumActiveAnalyses = 0
    private var analysisOrder: [String] = []

    func beginVolume() { activeVolumes += 1 }
    func endVolume() { activeVolumes -= 1 }

    func beginAnalysis(_ analysis: ScanEverythingAnalysis) {
        if activeVolumes > 0 { analysisOverlappedVolume = true }
        activeAnalyses += 1
        maximumActiveAnalyses = max(maximumActiveAnalyses, activeAnalyses)
        analysisOrder.append(analysis.rawValue)
    }

    func endAnalysis() { activeAnalyses -= 1 }

    var snapshot: Snapshot {
        Snapshot(
            analysisOverlappedVolume: analysisOverlappedVolume,
            maximumActiveAnalyses: maximumActiveAnalyses,
            analysisOrder: analysisOrder
        )
    }
}

private struct FailingAICodingAnalyzer: AICodingToolsAnalyzing {
    let timeline: OperationTimeline

    func analyze(
        request: AICodingToolsRequest,
        onProgress: @escaping @Sendable (AICodingToolsProgress) -> Void
    ) async throws -> AICodingToolsReport {
        await timeline.beginAnalysis(.aiCodingTools)
        try await Task.sleep(nanoseconds: 10_000_000)
        await timeline.endAnalysis()
        throw TestRunnerError.failed(ScanEverythingAnalysis.aiCodingTools.rawValue)
    }
}

private struct FailingAIModelsAnalyzer: AIModelsAndRuntimesAnalyzing {
    let timeline: OperationTimeline

    func analyze(
        request: AIModelsAndRuntimesRequest,
        onProgress: @escaping @Sendable (AIModelsProgress) -> Void
    ) async throws -> AIModelsAndRuntimesReport {
        await timeline.beginAnalysis(.aiModelsAndRuntimes)
        try await Task.sleep(nanoseconds: 10_000_000)
        await timeline.endAnalysis()
        throw TestRunnerError.failed(ScanEverythingAnalysis.aiModelsAndRuntimes.rawValue)
    }
}

private struct FailingDeveloperStorageAnalyzer: DeveloperStorageAnalyzing {
    let timeline: OperationTimeline

    func analyze(
        request: DeveloperStorageRequest,
        onProgress: @escaping @Sendable (DeveloperStorageProgress) -> Void
    ) async throws -> DeveloperStorageReport {
        await timeline.beginAnalysis(.developerStorage)
        try await Task.sleep(nanoseconds: 10_000_000)
        await timeline.endAnalysis()
        throw TestRunnerError.failed(ScanEverythingAnalysis.developerStorage.rawValue)
    }
}
