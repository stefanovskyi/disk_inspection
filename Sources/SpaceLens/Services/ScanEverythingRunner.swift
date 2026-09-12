import Dispatch
import Foundation
import os

protocol VolumeScanning: Sendable {
    func scan(
        url: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult
}

extension DiskScanner: VolumeScanning {}

protocol VolumeScannerFactory: Sendable {
    func makeScanner(traversalBudget: ScanTraversalBudget) -> any VolumeScanning
}

struct DefaultVolumeScannerFactory: VolumeScannerFactory {
    func makeScanner(traversalBudget: ScanTraversalBudget) -> any VolumeScanning {
        DiskScanner(
            maximumParallelism: traversalBudget.permitCount,
            traversalBudget: traversalBudget
        )
    }
}

struct ScanEverythingExecutionPolicy: Equatable, Sendable {
    let maximumConcurrentVolumeScans: Int
    let maximumDirectoryReaders: Int
    let maximumScansPerPhysicalDevice: Int
    let progressUpdatesPerSecond: Int

    init(
        maximumConcurrentVolumeScans: Int,
        maximumDirectoryReaders: Int,
        maximumScansPerPhysicalDevice: Int,
        progressUpdatesPerSecond: Int
    ) {
        precondition(maximumConcurrentVolumeScans > 0)
        precondition(maximumDirectoryReaders >= maximumConcurrentVolumeScans)
        precondition(maximumScansPerPhysicalDevice > 0)
        precondition(progressUpdatesPerSecond > 0)
        self.maximumConcurrentVolumeScans = maximumConcurrentVolumeScans
        self.maximumDirectoryReaders = maximumDirectoryReaders
        self.maximumScansPerPhysicalDevice = maximumScansPerPhysicalDevice
        self.progressUpdatesPerSecond = progressUpdatesPerSecond
    }

    static let adaptive = Self(
        maximumConcurrentVolumeScans: 2,
        maximumDirectoryReaders: 8,
        maximumScansPerPhysicalDevice: 1,
        progressUpdatesPerSecond: 10
    )

    static let sequential = Self(
        maximumConcurrentVolumeScans: 1,
        maximumDirectoryReaders: 8,
        maximumScansPerPhysicalDevice: 1,
        progressUpdatesPerSecond: 10
    )
}

struct ScanEverythingRequests: Sendable {
    let aiCodingTools: AICodingToolsRequest
    let aiModelsAndRuntimes: AIModelsAndRuntimesRequest
    let developerStorage: DeveloperStorageRequest
}

enum ScanEverythingEvent: Sendable {
    case progress(ScanEverythingProgress)
    case volumeCompleted(volume: VolumeInfo, result: ScanResult)
    case aiCodingToolsCompleted(AICodingToolsReport)
    case aiModelsAndRuntimesCompleted(AIModelsAndRuntimesReport)
    case developerStorageCompleted(DeveloperStorageReport)
    case stepFailed(step: ScanEverythingStep, message: String)
}

/// Owns all scheduling for Scan Everything. Volume scans may overlap only
/// across device keys; analyses deliberately remain a sequential second phase.
struct ScanEverythingRunner: Sendable {
    typealias EventHandler = @Sendable (ScanEverythingEvent) async -> Void

    private let executionPolicy: ScanEverythingExecutionPolicy
    private let volumeScannerFactory: any VolumeScannerFactory
    private let aiCodingToolsAnalyzer: any AICodingToolsAnalyzing
    private let aiModelsAndRuntimesAnalyzer: any AIModelsAndRuntimesAnalyzing
    private let developerStorageAnalyzer: any DeveloperStorageAnalyzing

    init(
        executionPolicy: ScanEverythingExecutionPolicy = .adaptive,
        volumeScannerFactory: any VolumeScannerFactory = DefaultVolumeScannerFactory(),
        aiCodingToolsAnalyzer: any AICodingToolsAnalyzing = AICodingToolsAnalyzer(),
        aiModelsAndRuntimesAnalyzer: any AIModelsAndRuntimesAnalyzing = AIModelsAndRuntimesAnalyzer(),
        developerStorageAnalyzer: any DeveloperStorageAnalyzing = DeveloperStorageAnalyzer()
    ) {
        self.executionPolicy = executionPolicy
        self.volumeScannerFactory = volumeScannerFactory
        self.aiCodingToolsAnalyzer = aiCodingToolsAnalyzer
        self.aiModelsAndRuntimesAnalyzer = aiModelsAndRuntimesAnalyzer
        self.developerStorageAnalyzer = developerStorageAnalyzer
    }

    func run(
        plan: ScanEverythingPlan,
        requests: ScanEverythingRequests,
        onEvent: @escaping EventHandler = { _ in }
    ) async throws -> ScanEverythingSummary {
        let startedAt = Date()
        let signposter = SpaceLensSignposts.scanEverything
        let signpostID = signposter.makeSignpostID()
        let signpostState = signposter.beginInterval(
            "ScanEverything",
            id: signpostID,
            "steps=\(plan.steps.count) volumeConcurrency=\(executionPolicy.maximumConcurrentVolumeScans) readers=\(executionPolicy.maximumDirectoryReaders)"
        )
        defer { signposter.endInterval("ScanEverything", signpostState) }

        let pipeline = ScanEverythingEventPipeline(handler: onEvent)
        let progress = ScanEverythingProgressPublisher(
            plan: plan,
            updatesPerSecond: executionPolicy.progressUpdatesPerSecond,
            pipeline: pipeline
        )
        let traversalBudget = ScanTraversalBudget(
            permitCount: executionPolicy.maximumDirectoryReaders
        )

        do {
            let volumeOutcomes = try await runVolumePhase(
                plan: plan,
                traversalBudget: traversalBudget,
                progress: progress,
                pipeline: pipeline,
                signposter: signposter,
                signpostID: signpostID
            )
            let analysisOutcomes = try await runAnalysisPhase(
                analyses: plan.analyses,
                requests: requests,
                progress: progress,
                pipeline: pipeline,
                signposter: signposter,
                signpostID: signpostID
            )
            try Task.checkCancellation()
            await pipeline.finish()
            return ScanEverythingSummary(
                startedAt: startedAt,
                duration: max(Date().timeIntervalSince(startedAt), 0),
                outcomes: volumeOutcomes + analysisOutcomes
            )
        } catch {
            await pipeline.finish()
            if Task.isCancelled || Self.isCancellation(error) {
                throw CancellationError()
            }
            throw error
        }
    }

    private func runVolumePhase(
        plan: ScanEverythingPlan,
        traversalBudget: ScanTraversalBudget,
        progress: ScanEverythingProgressPublisher,
        pipeline: ScanEverythingEventPipeline,
        signposter: OSSignposter,
        signpostID: OSSignpostID
    ) async throws -> [ScanEverythingStepOutcome] {
        guard !plan.volumes.isEmpty else { return [] }
        let policy = executionPolicy
        let scannerFactory = volumeScannerFactory
        let memoryPressure = ScanEverythingMemoryPressureMonitor.shared

        let completions = try await withThrowingTaskGroup(
            of: VolumeScanCompletion.self,
            returning: [ScanEverythingStep.ID: VolumeScanCompletion].self
        ) { group in
            var pending = plan.volumes
            var activeByDevice: [ScanDeviceKey: Int] = [:]
            var activeCount = 0
            var completions: [ScanEverythingStep.ID: VolumeScanCompletion] = [:]

            while !pending.isEmpty || activeCount > 0 {
                try Task.checkCancellation()

                while activeCount < policy.maximumConcurrentVolumeScans,
                      !memoryPressure.isCritical,
                      let pendingIndex = pending.firstIndex(where: {
                          activeByDevice[$0.scanDeviceKey, default: 0]
                              < policy.maximumScansPerPhysicalDevice
                      }) {
                    let volume = pending.remove(at: pendingIndex)
                    let step = ScanEverythingStep.volume(volume)
                    let scanner = scannerFactory.makeScanner(traversalBudget: traversalBudget)
                    activeByDevice[volume.scanDeviceKey, default: 0] += 1
                    activeCount += 1
                    progress.start(step)
                    signposter.emitEvent(
                        "ScanEverythingStepStarted",
                        id: signpostID,
                        "step=\(step.id, privacy: .public)"
                    )

                    group.addTask {
                        try await Self.scanVolume(
                            volume,
                            scanner: scanner,
                            progress: progress,
                            pipeline: pipeline
                        )
                    }
                }

                if activeCount == 0 {
                    try await memoryPressure.waitUntilAdmissionIsSafe()
                    continue
                }

                guard let completion = try await group.next() else { break }
                activeCount -= 1
                activeByDevice[completion.volume.scanDeviceKey, default: 1] -= 1
                completions[completion.step.id] = completion
                await progress.complete(completion.step)
                Self.emitCompletionSignpost(
                    completion.outcome,
                    signposter: signposter,
                    signpostID: signpostID
                )
            }

            return completions
        }

        return plan.volumes.compactMap {
            completions[ScanEverythingStep.volume($0).id]?.outcome
        }
    }

    private static func scanVolume(
        _ volume: VolumeInfo,
        scanner: any VolumeScanning,
        progress: ScanEverythingProgressPublisher,
        pipeline: ScanEverythingEventPipeline
    ) async throws -> VolumeScanCompletion {
        let step = ScanEverythingStep.volume(volume)
        let startedAt = Date()
        do {
            let result = try await scanner.scan(
                url: volume.url,
                onProgress: { scanProgress in
                    let fraction = volume.usedCapacity > 0
                        ? min(
                            max(Double(scanProgress.mappedBytes) / Double(volume.usedCapacity), 0),
                            0.99
                        )
                        : nil
                    progress.update(
                        step: step,
                        currentLocationName: volume.name,
                        currentPath: scanProgress.currentPath,
                        itemsScanned: scanProgress.itemsScanned,
                        mappedBytes: scanProgress.mappedBytes,
                        fraction: fraction
                    )
                }
            )
            try Task.checkCancellation()
            await progress.flush(step)
            await pipeline.send(.volumeCompleted(volume: volume, result: result))
            return VolumeScanCompletion(
                volume: volume,
                outcome: .init(
                    step: step,
                    duration: max(Date().timeIntervalSince(startedAt), 0),
                    status: .completed
                )
            )
        } catch {
            if Task.isCancelled || isCancellation(error) { throw CancellationError() }
            await progress.flush(step)
            let message = error.localizedDescription
            await pipeline.send(.stepFailed(step: step, message: message))
            return VolumeScanCompletion(
                volume: volume,
                outcome: .init(
                    step: step,
                    duration: max(Date().timeIntervalSince(startedAt), 0),
                    status: .failed(message: message)
                )
            )
        }
    }

    private func runAnalysisPhase(
        analyses: [ScanEverythingAnalysis],
        requests: ScanEverythingRequests,
        progress: ScanEverythingProgressPublisher,
        pipeline: ScanEverythingEventPipeline,
        signposter: OSSignposter,
        signpostID: OSSignpostID
    ) async throws -> [ScanEverythingStepOutcome] {
        var outcomes: [ScanEverythingStepOutcome] = []

        for analysis in analyses {
            try Task.checkCancellation()
            let step = ScanEverythingStep.analysis(analysis)
            let startedAt = Date()
            progress.start(step)
            signposter.emitEvent(
                "ScanEverythingStepStarted",
                id: signpostID,
                "step=\(step.id, privacy: .public)"
            )

            do {
                try await runAnalysis(
                    analysis,
                    step: step,
                    requests: requests,
                    progress: progress,
                    pipeline: pipeline
                )
                let outcome = ScanEverythingStepOutcome(
                    step: step,
                    duration: max(Date().timeIntervalSince(startedAt), 0),
                    status: .completed
                )
                outcomes.append(outcome)
                await progress.complete(step)
                Self.emitCompletionSignpost(
                    outcome,
                    signposter: signposter,
                    signpostID: signpostID
                )
            } catch {
                if Task.isCancelled || Self.isCancellation(error) {
                    throw CancellationError()
                }
                await progress.flush(step)
                let message = error.localizedDescription
                await pipeline.send(.stepFailed(step: step, message: message))
                let outcome = ScanEverythingStepOutcome(
                    step: step,
                    duration: max(Date().timeIntervalSince(startedAt), 0),
                    status: .failed(message: message)
                )
                outcomes.append(outcome)
                await progress.complete(step)
                Self.emitCompletionSignpost(
                    outcome,
                    signposter: signposter,
                    signpostID: signpostID
                )
            }
        }

        return outcomes
    }

    private func runAnalysis(
        _ analysis: ScanEverythingAnalysis,
        step: ScanEverythingStep,
        requests: ScanEverythingRequests,
        progress: ScanEverythingProgressPublisher,
        pipeline: ScanEverythingEventPipeline
    ) async throws {
        switch analysis {
        case .aiCodingTools:
            let report = try await aiCodingToolsAnalyzer.analyze(
                request: requests.aiCodingTools,
                onProgress: { update in
                    progress.update(
                        step: step,
                        currentLocationName: update.currentLocationName,
                        currentPath: update.currentPath,
                        itemsScanned: update.itemsScanned,
                        mappedBytes: update.mappedBytes,
                        fraction: update.fractionCompleted
                    )
                }
            )
            try Task.checkCancellation()
            await progress.flush(step)
            await pipeline.send(.aiCodingToolsCompleted(report))

        case .aiModelsAndRuntimes:
            let report = try await aiModelsAndRuntimesAnalyzer.analyze(
                request: requests.aiModelsAndRuntimes,
                onProgress: { update in
                    progress.update(
                        step: step,
                        currentLocationName: update.currentLocationName,
                        currentPath: update.currentPath,
                        itemsScanned: update.itemsScanned,
                        mappedBytes: update.mappedBytes,
                        fraction: update.fractionCompleted
                    )
                }
            )
            try Task.checkCancellation()
            await progress.flush(step)
            await pipeline.send(.aiModelsAndRuntimesCompleted(report))

        case .developerStorage:
            let report = try await developerStorageAnalyzer.analyze(
                request: requests.developerStorage,
                onProgress: { update in
                    progress.update(
                        step: step,
                        currentLocationName: update.currentLocationName,
                        currentPath: update.currentPath,
                        itemsScanned: update.itemsScanned,
                        mappedBytes: update.mappedBytes,
                        fraction: update.fractionCompleted
                    )
                }
            )
            try Task.checkCancellation()
            await progress.flush(step)
            await pipeline.send(.developerStorageCompleted(report))
        }
    }

    private static func emitCompletionSignpost(
        _ outcome: ScanEverythingStepOutcome,
        signposter: OSSignposter,
        signpostID: OSSignpostID
    ) {
        switch outcome.status {
        case .completed:
            signposter.emitEvent(
                "ScanEverythingStepCompleted",
                id: signpostID,
                "step=\(outcome.step.id, privacy: .public) durationSeconds=\(outcome.duration)"
            )
        case .failed:
            signposter.emitEvent(
                "ScanEverythingStepFailed",
                id: signpostID,
                "step=\(outcome.step.id, privacy: .public)"
            )
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let failure = error as? ScanFailure, case .cancelled = failure { return true }
        return false
    }
}

private struct VolumeScanCompletion: Sendable {
    let volume: VolumeInfo
    let outcome: ScanEverythingStepOutcome

    var step: ScanEverythingStep { outcome.step }
}

/// Thread-safe progress state used by synchronous scanner callbacks. Callback
/// updates are coalesced before entering the single asynchronous event pipeline.
private final class ScanEverythingProgressPublisher: @unchecked Sendable {
    private let lock = NSLock()
    private let pipeline: ScanEverythingEventPipeline
    private let minimumUpdateIntervalNanoseconds: UInt64
    private var tracker: ScanEverythingProgressTracker
    private var lastCallbackEmission: UInt64 = 0
    private var lastEmittedProgress: ScanEverythingProgress?

    init(
        plan: ScanEverythingPlan,
        updatesPerSecond: Int,
        pipeline: ScanEverythingEventPipeline
    ) {
        tracker = ScanEverythingProgressTracker(plan: plan)
        minimumUpdateIntervalNanoseconds = 1_000_000_000 / UInt64(updatesPerSecond)
        self.pipeline = pipeline
    }

    func start(_ step: ScanEverythingStep) {
        lock.lock()
        tracker.start(step)
        let snapshot = tracker.snapshot
        lastEmittedProgress = snapshot
        lock.unlock()
        pipeline.enqueue(.progress(snapshot))
    }

    func update(
        step: ScanEverythingStep,
        currentLocationName: String?,
        currentPath: String?,
        itemsScanned: Int,
        mappedBytes: Int64,
        fraction: Double?
    ) {
        lock.lock()
        tracker.update(
            step: step,
            currentLocationName: currentLocationName,
            currentPath: currentPath,
            itemsScanned: itemsScanned,
            mappedBytes: mappedBytes,
            fraction: fraction
        )
        let now = DispatchTime.now().uptimeNanoseconds
        guard lastCallbackEmission == 0
                || now &- lastCallbackEmission >= minimumUpdateIntervalNanoseconds else {
            lock.unlock()
            return
        }
        lastCallbackEmission = now
        let snapshot = tracker.snapshot
        guard snapshot != lastEmittedProgress else {
            lock.unlock()
            return
        }
        lastEmittedProgress = snapshot
        lock.unlock()
        pipeline.enqueue(.progress(snapshot))
    }

    func flush(_ step: ScanEverythingStep) async {
        let snapshot = pendingFlushSnapshot()
        if let snapshot {
            await pipeline.send(.progress(snapshot))
        } else {
            await pipeline.flush()
        }
    }

    func complete(_ step: ScanEverythingStep) async {
        let snapshot = completionSnapshot(for: step)
        await pipeline.send(.progress(snapshot))
    }

    private func pendingFlushSnapshot() -> ScanEverythingProgress? {
        lock.lock()
        defer { lock.unlock() }
        let current = tracker.snapshot
        if current != lastEmittedProgress {
            lastEmittedProgress = current
            return current
        }
        return nil
    }

    private func completionSnapshot(for step: ScanEverythingStep) -> ScanEverythingProgress {
        lock.lock()
        defer { lock.unlock() }
        tracker.complete(step)
        let snapshot = tracker.snapshot
        lastEmittedProgress = snapshot
        return snapshot
    }
}

private struct ScanEverythingProgressTracker {
    private let stepsByID: [ScanEverythingStep.ID: ScanEverythingStep]
    private let volumeSteps: [ScanEverythingStep]
    private let analysisSteps: [ScanEverythingStep]
    private var activeOperations: [ScanEverythingStep.ID: ScanEverythingOperationProgress] = [:]
    private var completedStepIDs: Set<ScanEverythingStep.ID> = []
    private var maximumOverallFraction: Double = 0

    init(plan: ScanEverythingPlan) {
        let steps = plan.steps
        stepsByID = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
        volumeSteps = plan.volumes.map(ScanEverythingStep.volume)
        analysisSteps = plan.analyses.map(ScanEverythingStep.analysis)
    }

    mutating func start(_ step: ScanEverythingStep) {
        let locationName: String?
        if case .volume(let volume) = step {
            locationName = volume.name
        } else {
            locationName = nil
        }
        activeOperations[step.id] = ScanEverythingOperationProgress(
            step: step,
            currentLocationName: locationName
        )
        updateOverallFraction()
    }

    mutating func update(
        step: ScanEverythingStep,
        currentLocationName: String?,
        currentPath: String?,
        itemsScanned: Int,
        mappedBytes: Int64,
        fraction: Double?
    ) {
        guard var operation = activeOperations[step.id] else { return }
        if let currentLocationName { operation.currentLocationName = currentLocationName }
        if let currentPath { operation.currentPath = currentPath }
        operation.itemsScanned = max(operation.itemsScanned, itemsScanned)
        operation.mappedBytes = max(operation.mappedBytes, mappedBytes)
        if let fraction {
            operation.fraction = max(operation.fraction ?? 0, min(max(fraction, 0), 1))
        }
        activeOperations[step.id] = operation
        updateOverallFraction()
    }

    mutating func complete(_ step: ScanEverythingStep) {
        activeOperations.removeValue(forKey: step.id)
        completedStepIDs.insert(step.id)
        updateOverallFraction()
    }

    var snapshot: ScanEverythingProgress {
        ScanEverythingProgress(
            activeOperations: activeOperations,
            completedStepIDs: completedStepIDs,
            totalSteps: stepsByID.count,
            overallFraction: maximumOverallFraction
        )
    }

    private mutating func updateOverallFraction() {
        guard !stepsByID.isEmpty else {
            maximumOverallFraction = 1
            return
        }

        var completedUnits = 0.0
        if !volumeSteps.isEmpty {
            let capacities = volumeSteps.compactMap { step -> Int64? in
                guard case .volume(let volume) = step, volume.usedCapacity > 0 else { return nil }
                return volume.usedCapacity
            }
            if capacities.count == volumeSteps.count {
                let totalCapacity = capacities.reduce(0.0) { $0 + Double($1) }
                let mappedCapacity = volumeSteps.reduce(0.0) { partial, step in
                    guard case .volume(let volume) = step else { return partial }
                    if completedStepIDs.contains(step.id) {
                        return partial + Double(volume.usedCapacity)
                    }
                    let mapped = activeOperations[step.id]?.mappedBytes ?? 0
                    return partial + min(Double(mapped), Double(volume.usedCapacity))
                }
                if totalCapacity > 0 {
                    completedUnits += mappedCapacity / totalCapacity * Double(volumeSteps.count)
                }
            } else {
                completedUnits += Double(volumeSteps.count {
                    completedStepIDs.contains($0.id)
                })
            }
        }

        completedUnits += Double(analysisSteps.count {
            completedStepIDs.contains($0.id)
        })
        completedUnits += analysisSteps.reduce(0.0) { partial, step in
            partial + min(max(activeOperations[step.id]?.fraction ?? 0, 0), 1)
        }

        let candidate = min(max(completedUnits / Double(stepsByID.count), 0), 1)
        maximumOverallFraction = max(maximumOverallFraction, candidate)
    }
}

/// A single consumer preserves event order without creating a task for every
/// scanner callback. Acknowledged sends are used at operation boundaries.
private final class ScanEverythingEventPipeline: @unchecked Sendable {
    private let continuation: AsyncStream<ScanEverythingEventEnvelope>.Continuation
    private let worker: Task<Void, Never>

    init(handler: @escaping ScanEverythingRunner.EventHandler) {
        var streamContinuation: AsyncStream<ScanEverythingEventEnvelope>.Continuation!
        let stream = AsyncStream<ScanEverythingEventEnvelope> { continuation in
            streamContinuation = continuation
        }
        continuation = streamContinuation
        worker = Task {
            for await envelope in stream {
                if let event = envelope.event {
                    await handler(event)
                }
                envelope.acknowledgement?.resume()
            }
        }
    }

    deinit {
        continuation.finish()
        worker.cancel()
    }

    func enqueue(_ event: ScanEverythingEvent) {
        continuation.yield(ScanEverythingEventEnvelope(event: event))
    }

    func send(_ event: ScanEverythingEvent) async {
        await withCheckedContinuation { acknowledgement in
            let result = continuation.yield(
                ScanEverythingEventEnvelope(
                    event: event,
                    acknowledgement: acknowledgement
                )
            )
            if case .terminated = result {
                acknowledgement.resume()
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { acknowledgement in
            let result = continuation.yield(
                ScanEverythingEventEnvelope(
                    event: nil,
                    acknowledgement: acknowledgement
                )
            )
            if case .terminated = result {
                acknowledgement.resume()
            }
        }
    }

    func finish() async {
        continuation.finish()
        await worker.value
    }
}

private final class ScanEverythingEventEnvelope: @unchecked Sendable {
    let event: ScanEverythingEvent?
    let acknowledgement: CheckedContinuation<Void, Never>?

    init(
        event: ScanEverythingEvent?,
        acknowledgement: CheckedContinuation<Void, Never>? = nil
    ) {
        self.event = event
        self.acknowledgement = acknowledgement
    }
}

private final class ScanEverythingMemoryPressureMonitor: @unchecked Sendable {
    static let shared = ScanEverythingMemoryPressureMonitor()

    private let lock = NSLock()
    private let source: DispatchSourceMemoryPressure
    private var critical = false

    private init() {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: DispatchQueue(label: "com.spacelens.scan-everything-memory-pressure")
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            lock.lock()
            critical = source.data.contains(.critical)
            lock.unlock()
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    var isCritical: Bool {
        lock.lock()
        defer { lock.unlock() }
        return critical
    }

    func waitUntilAdmissionIsSafe() async throws {
        while isCritical {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
