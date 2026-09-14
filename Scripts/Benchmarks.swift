import Foundation

private func median<T: BinaryFloatingPoint>(_ values: [T]) -> T {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

enum BenchmarkFailure: LocalizedError {
    case invalidConfiguration(String)
    case fixtureCreation(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .fixtureCreation(let message):
            return message
        }
    }
}

struct BenchmarkConfiguration {
    let iterations: Int
    let selectedFixtures: Set<String>
    let flatFileCount: Int
    let deepDirectoryCount: Int
    let mixedDepth: Int
    let mixedFanout: Int
    let mixedFilesPerDirectory: Int
    let providerTimeout: TimeInterval
    let externalPath: String?
    let scannerParallelism: Int
    let volumeScanLimit: Int
    let directoryBufferSize: Int
    let outputDirectory: URL
    let runID: String
    let gitRevision: String
    let gitDirty: Bool
    let sdkPath: String
    let swiftVersion: String
    let tracePath: String?
    let traceTemplate: String?
    let fullDiskAccessGranted: Bool?

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        let knownFixtures = Set([
            "flat", "flat-observer", "deep", "mixed", "mixed-live-preview",
            "mixed-counts-only", "provider", "multi-volume", "external", "full-disk",
            "full-disk-live-preview", "full-disk-counts-only"
        ])
        let defaultFixtures = Set(["flat", "deep", "mixed", "provider", "multi-volume"])
        let requestedFixtures = environment["SPACELENS_BENCHMARK_FIXTURES"]
            .map {
                Set(
                    $0.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty }
                )
            }
            ?? defaultFixtures
        let unknownFixtures = requestedFixtures.subtracting(knownFixtures)
        guard unknownFixtures.isEmpty else {
            throw BenchmarkFailure.invalidConfiguration(
                "Unknown benchmark fixture(s): \(unknownFixtures.sorted().joined(separator: ", "))"
            )
        }

        let runID = environment["SPACELENS_BENCHMARK_RUN_ID"] ?? UUID().uuidString
        guard !runID.isEmpty,
              runID != ".",
              runID != "..",
              runID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
            throw BenchmarkFailure.invalidConfiguration(
                "SPACELENS_BENCHMARK_RUN_ID may contain only letters, numbers, periods, hyphens, and underscores"
            )
        }

        let suggestedParallelism = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        let directoryBufferKilobytes = try positiveInteger(
            "SPACELENS_BENCHMARK_DIRECTORY_BUFFER_KB",
            default: BulkDirectoryReader.defaultBufferSize / 1024,
            environment: environment
        )
        guard directoryBufferKilobytes >= BulkDirectoryReader.minimumBufferSize / 1024,
              directoryBufferKilobytes <= Int.max / 1024 else {
            throw BenchmarkFailure.invalidConfiguration(
                "SPACELENS_BENCHMARK_DIRECTORY_BUFFER_KB must be at least "
                    + "\(BulkDirectoryReader.minimumBufferSize / 1024)"
            )
        }
        let fullDiskAccessGranted = requestedFixtures.contains(where: {
            $0 == "full-disk"
                || $0 == "full-disk-live-preview"
                || $0 == "full-disk-counts-only"
        })
            ? FullDiskAccessChecker().status() == .granted
            : nil
        return BenchmarkConfiguration(
            iterations: try positiveInteger("SPACELENS_BENCHMARK_ITERATIONS", default: 3, environment: environment),
            selectedFixtures: requestedFixtures,
            flatFileCount: try positiveInteger("SPACELENS_BENCHMARK_FLAT_FILES", default: 12_000, environment: environment),
            deepDirectoryCount: try positiveInteger("SPACELENS_BENCHMARK_DEEP_DIRECTORIES", default: 96, environment: environment),
            mixedDepth: try positiveInteger("SPACELENS_BENCHMARK_MIXED_DEPTH", default: 3, environment: environment),
            mixedFanout: try positiveInteger("SPACELENS_BENCHMARK_MIXED_FANOUT", default: 6, environment: environment),
            mixedFilesPerDirectory: try positiveInteger(
                "SPACELENS_BENCHMARK_MIXED_FILES_PER_DIRECTORY",
                default: 12,
                environment: environment
            ),
            providerTimeout: TimeInterval(
                try positiveInteger("SPACELENS_BENCHMARK_PROVIDER_TIMEOUT_MS", default: 75, environment: environment)
            ) / 1_000,
            externalPath: environment["SPACELENS_BENCHMARK_EXTERNAL_PATH"],
            scannerParallelism: try positiveInteger(
                "SPACELENS_BENCHMARK_PARALLELISM",
                default: suggestedParallelism,
                environment: environment
            ),
            volumeScanLimit: try positiveInteger(
                "SPACELENS_BENCHMARK_VOLUME_SCAN_LIMIT",
                default: 2,
                environment: environment
            ),
            directoryBufferSize: directoryBufferKilobytes * 1024,
            outputDirectory: URL(
                fileURLWithPath: environment["SPACELENS_BENCHMARK_OUTPUT_DIR"]
                    ?? FileManager.default.currentDirectoryPath,
                isDirectory: true
            ),
            runID: runID,
            gitRevision: environment["SPACELENS_BENCHMARK_GIT_REVISION"] ?? "unknown",
            gitDirty: environment["SPACELENS_BENCHMARK_GIT_DIRTY"] == "true",
            sdkPath: environment["SPACELENS_BENCHMARK_SDK_PATH"] ?? "unknown",
            swiftVersion: environment["SPACELENS_BENCHMARK_SWIFT_VERSION"] ?? "unknown",
            tracePath: environment["SPACELENS_BENCHMARK_TRACE_PATH"],
            traceTemplate: environment["SPACELENS_BENCHMARK_TRACE_PATH"] == nil
                ? nil
                : environment["SPACELENS_BENCHMARK_TRACE_TEMPLATE"],
            fullDiskAccessGranted: fullDiskAccessGranted
        )
    }

    private static func positiveInteger(
        _ key: String,
        default defaultValue: Int,
        environment: [String: String]
    ) throws -> Int {
        guard let rawValue = environment[key] else { return defaultValue }
        guard let value = Int(rawValue), value > 0 else {
            throw BenchmarkFailure.invalidConfiguration("\(key) must be a positive integer")
        }
        return value
    }
}

struct BenchmarkMeasurement {
    let name: String
    let scanDurations: [TimeInterval]
    let layoutDurations: [TimeInterval]
    let cachedHoverDurations: [TimeInterval]
    let itemCounts: [Int]
    let segmentCounts: [Int]
    let unreadableCounts: [Int]
    let diagnostics: [ScanDiagnosticSnapshot]
    let maximumDirectoryReaderCounts: [Int?]
    let cancellationLatencies: [TimeInterval?]

    var medianScanDuration: TimeInterval { median(scanDurations) }
    var fastestScanDuration: TimeInterval { scanDurations.min() ?? 0 }
    var slowestScanDuration: TimeInterval { scanDurations.max() ?? 0 }
    var meanScanDuration: TimeInterval {
        guard !scanDurations.isEmpty else { return 0 }
        return scanDurations.reduce(0, +) / Double(scanDurations.count)
    }
    var scanDurationStandardDeviation: TimeInterval {
        guard scanDurations.count > 1 else { return 0 }
        let squaredDifferences = scanDurations.map { duration in
            let difference = duration - meanScanDuration
            return difference * difference
        }
        return sqrt(squaredDifferences.reduce(0, +) / Double(scanDurations.count - 1))
    }
    var variabilityFraction: Double {
        guard medianScanDuration > 0 else { return 0 }
        return (slowestScanDuration - fastestScanDuration) / medianScanDuration
    }
    var medianLayoutDuration: TimeInterval { median(layoutDurations) }
    var medianCachedHoverDuration: TimeInterval { median(cachedHoverDurations) }
    var medianItemCount: Int { Int(median(itemCounts.map(Double.init))) }
    var medianSegmentCount: Int { Int(median(segmentCounts.map(Double.init))) }
    var maximumUnreadableCount: Int { unreadableCounts.max() ?? 0 }
    var maximumDirectoryReaderCount: Int? {
        maximumDirectoryReaderCounts.compactMap { $0 }.max()
    }
    var medianCancellationLatency: TimeInterval? {
        let values = cancellationLatencies.compactMap { $0 }
        return values.isEmpty ? nil : median(values)
    }
    var itemsPerSecond: Double {
        guard medianScanDuration > 0 else { return 0 }
        return Double(medianItemCount) / medianScanDuration
    }
}

private struct BenchmarkOperationMeasurement {
    let result: ScanResult
    let maximumDirectoryReaders: Int?
    let cancellationLatency: TimeInterval?
    let scanDuration: TimeInterval?

    init(
        result: ScanResult,
        maximumDirectoryReaders: Int? = nil,
        cancellationLatency: TimeInterval? = nil,
        scanDuration: TimeInterval? = nil
    ) {
        self.result = result
        self.maximumDirectoryReaders = maximumDirectoryReaders
        self.cancellationLatency = cancellationLatency
        self.scanDuration = scanDuration
    }
}

@main
struct SpaceLensBenchmarks {
    private static let payload = Data(repeating: 0xA5, count: 4_096)

    static func main() async throws {
        let configuration = try BenchmarkConfiguration.load()
        let benchmarkStartedAt = Date()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBenchmarks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        print("SpaceLens release benchmarks")
        print("Run ID: \(configuration.runID)")
        print("Iterations: \(configuration.iterations)")
        print("Scanner parallelism: \(configuration.scannerParallelism)")
        print("Directory buffer: \(configuration.directoryBufferSize / 1024) KB")
        print("Fixture setup and cleanup are not timed. Results are warm-cache measurements.")

        var measurements: [BenchmarkMeasurement] = []

        if configuration.selectedFixtures.contains("flat")
            || configuration.selectedFixtures.contains("flat-observer") {
            let root = fixtureRoot.appendingPathComponent("Flat", isDirectory: true)
            print("Preparing flat fixture (\(configuration.flatFileCount) files)...")
            try createFlatFixture(at: root, fileCount: configuration.flatFileCount)
            if configuration.selectedFixtures.contains("flat") {
                measurements.append(
                    try await measure(name: "flat", iterations: configuration.iterations) {
                        try await DiskScanner(
                            maximumParallelism: configuration.scannerParallelism,
                            directoryBufferSize: configuration.directoryBufferSize
                        ).scan(url: root)
                    }
                )
            }
            if configuration.selectedFixtures.contains("flat-observer") {
                measurements.append(
                    try await measure(name: "flat-observer", iterations: configuration.iterations) {
                        try await DiskScanner(
                            maximumParallelism: configuration.scannerParallelism,
                            directoryBufferSize: configuration.directoryBufferSize
                        ).scan(url: root, onItem: { _ in })
                    }
                )
            }
        }

        if configuration.selectedFixtures.contains("deep") {
            let root = fixtureRoot.appendingPathComponent("Deep", isDirectory: true)
            print("Preparing deep fixture (\(configuration.deepDirectoryCount) nested directories)...")
            try createDeepFixture(at: root, directoryCount: configuration.deepDirectoryCount)
            measurements.append(
                try await measure(name: "deep", iterations: configuration.iterations) {
                    try await DiskScanner(
                        maximumParallelism: configuration.scannerParallelism,
                        directoryBufferSize: configuration.directoryBufferSize
                    ).scan(url: root)
                }
            )
        }

        if configuration.selectedFixtures.contains("mixed")
            || configuration.selectedFixtures.contains("mixed-live-preview")
            || configuration.selectedFixtures.contains("mixed-counts-only") {
            let root = fixtureRoot.appendingPathComponent("Mixed", isDirectory: true)
            print(
                "Preparing mixed fixture (depth \(configuration.mixedDepth), "
                    + "fanout \(configuration.mixedFanout), "
                    + "\(configuration.mixedFilesPerDirectory) files/directory)..."
            )
            try createMixedFixture(
                at: root,
                depth: configuration.mixedDepth,
                fanout: configuration.mixedFanout,
                filesPerDirectory: configuration.mixedFilesPerDirectory
            )
            let variants: [(name: String, policy: ScanPreviewPolicy)] = [
                ("mixed", .live),
                ("mixed-live-preview", .live),
                ("mixed-counts-only", .countsOnly)
            ]
            for variant in variants where configuration.selectedFixtures.contains(variant.name) {
                measurements.append(
                    try await measure(name: variant.name, iterations: configuration.iterations) {
                        try await DiskScanner(
                            maximumParallelism: configuration.scannerParallelism,
                            directoryBufferSize: configuration.directoryBufferSize,
                            previewPolicy: variant.policy
                        ).scan(url: root)
                    }
                )
            }
        }

        if configuration.selectedFixtures.contains("multi-volume") {
            let roots = (1...3).map {
                fixtureRoot.appendingPathComponent("Volume\($0)", isDirectory: true)
            }
            print("Preparing three disjoint synthetic volume roots...")
            for root in roots {
                try createMixedFixture(
                    at: root,
                    depth: max(configuration.mixedDepth - 1, 1),
                    fanout: configuration.mixedFanout,
                    filesPerDirectory: configuration.mixedFilesPerDirectory
                )
            }
            measurements.append(
                try await measureDetailed(
                    name: "multi-volume-sequential",
                    iterations: configuration.iterations
                ) {
                    try await measureVolumeBatch(
                        roots: roots,
                        maximumConcurrentScans: 1,
                        directoryReaders: configuration.scannerParallelism,
                        directoryBufferSize: configuration.directoryBufferSize,
                        fixtureRoot: fixtureRoot
                    )
                }
            )
            measurements.append(
                try await measureDetailed(
                    name: "multi-volume-parallel",
                    iterations: configuration.iterations
                ) {
                    try await measureVolumeBatch(
                        roots: roots,
                        maximumConcurrentScans: configuration.volumeScanLimit,
                        directoryReaders: configuration.scannerParallelism,
                        directoryBufferSize: configuration.directoryBufferSize,
                        fixtureRoot: fixtureRoot
                    )
                }
            )
        }

        if configuration.selectedFixtures.contains("provider") {
            let root = fixtureRoot.appendingPathComponent("ProviderTimeout", isDirectory: true)
            try createProviderFixture(at: root)
            measurements.append(
                try await measure(name: "provider", iterations: configuration.iterations) {
                    let gate = DispatchSemaphore(value: 0)
                    let scanner = DiskScanner(
                        maximumParallelism: configuration.scannerParallelism,
                        directoryBufferSize: configuration.directoryBufferSize,
                        stalledSubtreeTimeout: configuration.providerTimeout,
                        shouldIsolateSubtree: { $0.lastPathComponent == "Blocked" },
                        directoryReader: { url, keys in
                            if url.lastPathComponent == "Blocked" {
                                gate.wait()
                                return []
                            }
                            return try FileManager.default.contentsOfDirectory(
                                at: url,
                                includingPropertiesForKeys: keys,
                                options: []
                            )
                        }
                    )

                    do {
                        let result = try await scanner.scan(url: root)
                        gate.signal()
                        return result
                    } catch {
                        gate.signal()
                        throw error
                    }
                }
            )
        }

        if configuration.selectedFixtures.contains("full-disk")
            || configuration.selectedFixtures.contains("full-disk-live-preview")
            || configuration.selectedFixtures.contains("full-disk-counts-only") {
            let root = URL(fileURLWithPath: "/", isDirectory: true)
            guard configuration.fullDiskAccessGranted == true else {
                throw BenchmarkFailure.invalidConfiguration(
                    "The benchmark process needs Full Disk Access for a complete full-disk measurement"
                )
            }
            print("Full-disk fixture is read-only and will scan the startup volume: /")
            let variants: [(name: String, policy: ScanPreviewPolicy)] = [
                ("full-disk", .live),
                ("full-disk-live-preview", .live),
                ("full-disk-counts-only", .countsOnly)
            ]
            for variant in variants where configuration.selectedFixtures.contains(variant.name) {
                measurements.append(
                    try await measure(name: variant.name, iterations: configuration.iterations) {
                        try await DiskScanner(
                            maximumParallelism: configuration.scannerParallelism,
                            directoryBufferSize: configuration.directoryBufferSize,
                            excludedURLs: configuration.tracePath.map {
                                [URL(fileURLWithPath: $0, isDirectory: true)]
                            } ?? [],
                            previewPolicy: variant.policy
                        ).scan(url: root)
                    }
                )
            }
        }

        if configuration.selectedFixtures.contains("external") {
            if let externalPath = configuration.externalPath {
                let externalURL = URL(fileURLWithPath: externalPath, isDirectory: true).standardizedFileURL
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: externalURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw BenchmarkFailure.invalidConfiguration(
                        "SPACELENS_BENCHMARK_EXTERNAL_PATH must identify a readable directory"
                    )
                }
                print("External fixture is read-only and will scan: \(externalURL.path)")
                measurements.append(
                    try await measure(name: "external", iterations: configuration.iterations) {
                        try await DiskScanner(
                            maximumParallelism: configuration.scannerParallelism,
                            directoryBufferSize: configuration.directoryBufferSize
                        ).scan(url: externalURL)
                    }
                )
            } else {
                print("Skipping external: set SPACELENS_BENCHMARK_EXTERNAL_PATH to an external-disk fixture directory.")
            }
        }

        printSummary(measurements)
        let reportURLs = try BenchmarkReportWriter.write(
            configuration: configuration,
            measurements: measurements,
            startedAt: benchmarkStartedAt,
            finishedAt: Date()
        )
        print("JSON report: \(reportURLs.json.path)")
        print("CSV report:  \(reportURLs.csv.path)")
    }

    private static func measure(
        name: String,
        iterations: Int,
        operation: () async throws -> ScanResult
    ) async throws -> BenchmarkMeasurement {
        try await measureDetailed(name: name, iterations: iterations) {
            BenchmarkOperationMeasurement(result: try await operation())
        }
    }

    private static func measureDetailed(
        name: String,
        iterations: Int,
        operation: () async throws -> BenchmarkOperationMeasurement
    ) async throws -> BenchmarkMeasurement {
        var scanDurations: [TimeInterval] = []
        var layoutDurations: [TimeInterval] = []
        var cachedHoverDurations: [TimeInterval] = []
        var itemCounts: [Int] = []
        var segmentCounts: [Int] = []
        var unreadableCounts: [Int] = []
        var diagnostics: [ScanDiagnosticSnapshot] = []
        var maximumDirectoryReaderCounts: [Int?] = []
        var cancellationLatencies: [TimeInterval?] = []

        for iteration in 1...iterations {
            let signposter = SpaceLensSignposts.benchmark
            let signpostState = signposter.beginInterval(
                "BenchmarkIteration",
                "fixture=\(name, privacy: .public) iteration=\(iteration)"
            )
            let scanStart = DispatchTime.now().uptimeNanoseconds
            let operationMeasurement: BenchmarkOperationMeasurement
            do {
                operationMeasurement = try await operation()
            } catch {
                signposter.endInterval("BenchmarkIteration", signpostState, "failed=true")
                throw error
            }
            let scanEnd = DispatchTime.now().uptimeNanoseconds
            let result = operationMeasurement.result

            let layoutStart = DispatchTime.now().uptimeNanoseconds
            let scene = SunburstScene(
                root: result.root,
                maxDepth: 6,
                angularExtent: .pi * 2,
                interactionRadius: 100,
                policy: .interactive
            )
            let layoutEnd = DispatchTime.now().uptimeNanoseconds
            let cachedHoverStart = DispatchTime.now().uptimeNanoseconds
            var hoverMatchCount = 0
            if !scene.segments.isEmpty {
                for event in 0..<120 {
                    let segment = scene.segments[event % scene.segments.count]
                    let midpoint = segment.startAngle + (segment.angularSpan / 2)
                    if scene.segmentIndex(atDepth: segment.depth, angle: midpoint) != nil {
                        hoverMatchCount += 1
                    }
                }
            }
            let cachedHoverEnd = DispatchTime.now().uptimeNanoseconds
            precondition(scene.segments.isEmpty || hoverMatchCount == 120)
            signposter.endInterval(
                "BenchmarkIteration",
                signpostState,
                "items=\(result.itemsScanned) segments=\(scene.segments.count)"
            )

            let scanDuration = operationMeasurement.scanDuration
                ?? seconds(from: scanStart, to: scanEnd)
            let layoutDuration = seconds(from: layoutStart, to: layoutEnd)
            let cachedHoverDuration = seconds(from: cachedHoverStart, to: cachedHoverEnd)
            scanDurations.append(scanDuration)
            layoutDurations.append(layoutDuration)
            cachedHoverDurations.append(cachedHoverDuration)
            itemCounts.append(result.itemsScanned)
            segmentCounts.append(scene.segments.count)
            unreadableCounts.append(result.unreadableItems)
            diagnostics.append(result.diagnostics)
            maximumDirectoryReaderCounts.append(operationMeasurement.maximumDirectoryReaders)
            cancellationLatencies.append(operationMeasurement.cancellationLatency)

            print(
                String(
                    format: "  %-9s run %d: %.4f s, %d items, %.3f ms scene, %.3f ms/120 hover lookups, %d segments",
                    (name as NSString).utf8String!,
                    iteration,
                    scanDuration,
                    result.itemsScanned,
                    layoutDuration * 1_000,
                    cachedHoverDuration * 1_000,
                    scene.segments.count
                )
            )
            if let maximumDirectoryReaders = operationMeasurement.maximumDirectoryReaders,
               let cancellationLatency = operationMeasurement.cancellationLatency {
                print(
                    String(
                        format: "    batch: maximum-readers=%d cancellation-latency=%.3f ms",
                        maximumDirectoryReaders,
                        cancellationLatency * 1_000
                    )
                )
            }
            let diagnostics = result.diagnostics
            print(
                "    counters: batches=\(diagnostics.syscallBatches) "
                    + "fallback-lstat=\(diagnostics.fallbackLstatCalls) "
                    + "buffers=\(diagnostics.bufferAllocations) "
                    + "directory-tasks=\(diagnostics.directoryTasks) "
                    + "directories=\(diagnostics.directoryCount) "
                    + "retained=\(diagnostics.retainedNodes) "
                    + "discarded=\(diagnostics.discardedNodes) "
                    + "progress-merges=\(diagnostics.progressMerges) "
                    + "progress-emissions=\(diagnostics.progressEmissions) "
                    + "progress-locks=\(diagnostics.progressLockAcquisitions) "
                    + "worker-flushes=\(diagnostics.workerProgressFlushes) "
                    + "forced-flushes=\(diagnostics.forcedProgressFlushes) "
                    + "provider-timeouts=\(diagnostics.providerTimeouts) "
                    + "abandoned-workers=\(diagnostics.abandonedWorkers)"
            )
            print(
                "    preview: byte-merges=\(diagnostics.previewMappedByteMerges) "
                    + "branch-resolutions=\(diagnostics.rootPreviewBranchResolutions) "
                    + "completion-attempts=\(diagnostics.completedPreviewAttempts) "
                    + "completion-accepted=\(diagnostics.completedPreviewAccepted) "
                    + "constructions=\(diagnostics.previewConstructions) "
                    + "emissions=\(diagnostics.previewEmissions)"
            )
            print(
                String(
                    format: "    progress lock: wait=%.3f ms hold=%.3f ms",
                    Double(diagnostics.progressLockWaitNanoseconds) / 1_000_000,
                    Double(diagnostics.progressLockHoldNanoseconds) / 1_000_000
                )
            )
            print(
                String(
                    format: "    arena: nodes=%d construction=%.3f ms rss-before=%.1f MiB rss-after=%.1f MiB",
                    diagnostics.retainedArenaNodeCount,
                    diagnostics.arenaConstructionDurationSeconds * 1_000,
                    Double(diagnostics.rssBeforeArenaConstructionBytes) / 1_048_576,
                    Double(diagnostics.rssAfterArenaConstructionBytes) / 1_048_576
                )
            )
        }

        return BenchmarkMeasurement(
            name: name,
            scanDurations: scanDurations,
            layoutDurations: layoutDurations,
            cachedHoverDurations: cachedHoverDurations,
            itemCounts: itemCounts,
            segmentCounts: segmentCounts,
            unreadableCounts: unreadableCounts,
            diagnostics: diagnostics,
            maximumDirectoryReaderCounts: maximumDirectoryReaderCounts,
            cancellationLatencies: cancellationLatencies
        )
    }

    private static func measureVolumeBatch(
        roots: [URL],
        maximumConcurrentScans: Int,
        directoryReaders: Int,
        directoryBufferSize: Int,
        fixtureRoot: URL
    ) async throws -> BenchmarkOperationMeasurement {
        let budget = ScanTraversalBudget(permitCount: directoryReaders)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var results: [ScanResult] = []

        try await withThrowingTaskGroup(of: ScanResult.self) { group in
            var nextRoot = 0
            var activeScans = 0
            while nextRoot < roots.count || activeScans > 0 {
                while activeScans < maximumConcurrentScans, nextRoot < roots.count {
                    let root = roots[nextRoot]
                    nextRoot += 1
                    activeScans += 1
                    group.addTask {
                        try await DiskScanner(
                            maximumParallelism: directoryReaders,
                            directoryBufferSize: directoryBufferSize,
                            traversalBudget: budget
                        ).scan(url: root)
                    }
                }
                if let result = try await group.next() {
                    activeScans -= 1
                    results.append(result)
                }
            }
        }

        let finishedAt = DispatchTime.now().uptimeNanoseconds
        let scanDuration = seconds(from: startedAt, to: finishedAt)
        let cancellationLatency = try await measureBatchCancellationLatency(
            maximumConcurrentScans: maximumConcurrentScans,
            directoryReaders: directoryReaders,
            directoryBufferSize: directoryBufferSize,
            fixtureRoot: fixtureRoot
        )
        return BenchmarkOperationMeasurement(
            result: aggregateVolumeResults(results, at: fixtureRoot, duration: scanDuration),
            maximumDirectoryReaders: budget.snapshot.maximumObservedReaders,
            cancellationLatency: cancellationLatency,
            scanDuration: scanDuration
        )
    }

    private static func measureBatchCancellationLatency(
        maximumConcurrentScans: Int,
        directoryReaders: Int,
        directoryBufferSize: Int,
        fixtureRoot: URL
    ) async throws -> TimeInterval {
        let cancellationRoot = fixtureRoot.appendingPathComponent(
            "Cancellation-\(UUID().uuidString)",
            isDirectory: true
        )
        let rootCount = min(maximumConcurrentScans, 2)
        let roots = (0..<rootCount).map {
            cancellationRoot.appendingPathComponent("Root\($0)", isDirectory: true)
        }
        for root in roots {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Blocked", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: cancellationRoot) }

        let gate = BenchmarkCancellationGate()
        let budget = ScanTraversalBudget(permitCount: directoryReaders)
        let task = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for root in roots {
                    group.addTask {
                        let scanner = DiskScanner(
                            maximumParallelism: directoryReaders,
                            directoryBufferSize: directoryBufferSize,
                            stalledSubtreeTimeout: 30,
                            shouldIsolateSubtree: { $0.lastPathComponent == "Blocked" },
                            directoryReader: { url, keys in
                                if url.lastPathComponent == "Blocked" {
                                    gate.markStartedAndWait()
                                    return []
                                }
                                return try FileManager.default.contentsOfDirectory(
                                    at: url,
                                    includingPropertiesForKeys: keys,
                                    options: []
                                )
                            },
                            traversalBudget: budget
                        )
                        _ = try await scanner.scan(url: root)
                    }
                }
                try await group.waitForAll()
            }
        }

        for _ in 0..<1_000 where gate.startedCount < rootCount {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        guard gate.startedCount == rootCount else {
            task.cancel()
            gate.releaseAll()
            throw BenchmarkFailure.fixtureCreation("Cancellation benchmark workers did not start")
        }

        let cancellationStartedAt = DispatchTime.now().uptimeNanoseconds
        task.cancel()
        do {
            try await task.value
        } catch {
            // Cancellation is the expected terminal state.
        }
        let cancellationFinishedAt = DispatchTime.now().uptimeNanoseconds
        gate.releaseAll()
        try await Task.sleep(nanoseconds: 60_000_000)
        return seconds(from: cancellationStartedAt, to: cancellationFinishedAt)
    }

    private static func aggregateVolumeResults(
        _ results: [ScanResult],
        at fixtureRoot: URL,
        duration: TimeInterval
    ) -> ScanResult {
        let sortedResults = results.sorted { $0.root.url.path < $1.root.url.path }
        let totalSize = sortedResults.reduce(Int64(0)) { $0 + $1.root.size }
        let itemCount = sortedResults.reduce(0) { $0 + $1.itemsScanned }
        let unreadableItems = sortedResults.reduce(0) { $0 + $1.unreadableItems }
        var diagnostics = ScanDiagnosticSnapshot()
        for result in sortedResults {
            let value = result.diagnostics
            diagnostics.syscallBatches += value.syscallBatches
            diagnostics.fallbackLstatCalls += value.fallbackLstatCalls
            diagnostics.bufferAllocations += value.bufferAllocations
            diagnostics.directoryTasks += value.directoryTasks
            diagnostics.directoryCount += value.directoryCount
            diagnostics.retainedNodes += value.retainedNodes
            diagnostics.discardedNodes += value.discardedNodes
            diagnostics.progressMerges += value.progressMerges
            diagnostics.progressEmissions += value.progressEmissions
            diagnostics.progressLockAcquisitions += value.progressLockAcquisitions
            diagnostics.progressLockWaitNanoseconds += value.progressLockWaitNanoseconds
            diagnostics.progressLockHoldNanoseconds += value.progressLockHoldNanoseconds
            diagnostics.previewMappedByteMerges += value.previewMappedByteMerges
            diagnostics.rootPreviewBranchResolutions += value.rootPreviewBranchResolutions
            diagnostics.completedPreviewAttempts += value.completedPreviewAttempts
            diagnostics.completedPreviewAccepted += value.completedPreviewAccepted
            diagnostics.previewConstructions += value.previewConstructions
            diagnostics.previewEmissions += value.previewEmissions
            diagnostics.workerProgressFlushes += value.workerProgressFlushes
            diagnostics.forcedProgressFlushes += value.forcedProgressFlushes
            diagnostics.providerTimeouts += value.providerTimeouts
            diagnostics.abandonedWorkers += value.abandonedWorkers
            diagnostics.retainedArenaNodeCount += value.retainedArenaNodeCount
            diagnostics.arenaConstructionDurationSeconds += value.arenaConstructionDurationSeconds
            diagnostics.rssBeforeArenaConstructionBytes = max(
                diagnostics.rssBeforeArenaConstructionBytes,
                value.rssBeforeArenaConstructionBytes
            )
            diagnostics.rssAfterArenaConstructionBytes = max(
                diagnostics.rssAfterArenaConstructionBytes,
                value.rssAfterArenaConstructionBytes
            )
        }
        return ScanResult(
            root: FileNode(
                url: fixtureRoot,
                name: "Synthetic Volumes",
                size: totalSize,
                isDirectory: true,
                isReadable: true,
                children: sortedResults.map(\.root),
                itemCount: max(itemCount, 1),
                directItemCount: sortedResults.count
            ),
            duration: duration,
            itemsScanned: itemCount,
            unreadableItems: unreadableItems,
            diagnostics: diagnostics
        )
    }

    private static func createFlatFixture(at root: URL, fileCount: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<fileCount {
            try createFile(at: root.appendingPathComponent(String(format: "file-%06d.bin", index)))
        }
    }

    private static func createDeepFixture(at root: URL, directoryCount: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var current = root
        for index in 0..<directoryCount {
            try createFile(at: current.appendingPathComponent("payload.bin"))
            current.appendPathComponent("d\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
        }
        try createFile(at: current.appendingPathComponent("payload.bin"))
    }

    private static func createMixedFixture(
        at root: URL,
        depth: Int,
        fanout: Int,
        filesPerDirectory: Int
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        func populate(_ directory: URL, level: Int) throws {
            for index in 0..<filesPerDirectory {
                try createFile(at: directory.appendingPathComponent(String(format: "file-%03d.bin", index)))
            }
            guard level < depth else { return }

            for index in 0..<fanout {
                let child = directory.appendingPathComponent("branch-\(level)-\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
                try populate(child, level: level + 1)
            }
        }

        try populate(root, level: 0)
    }

    private static func createProviderFixture(at root: URL) throws {
        let blocked = root.appendingPathComponent("Blocked", isDirectory: true)
        let healthy = root.appendingPathComponent("Healthy", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: healthy, withIntermediateDirectories: true)
        try createFile(at: healthy.appendingPathComponent("payload.bin"))
    }

    private static func createFile(at url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: payload) else {
            throw BenchmarkFailure.fixtureCreation("Could not create benchmark fixture file at \(url.path)")
        }
    }

    private static func seconds(from start: UInt64, to end: UInt64) -> TimeInterval {
        TimeInterval(end &- start) / 1_000_000_000
    }

    private static func printSummary(_ measurements: [BenchmarkMeasurement]) {
        guard !measurements.isEmpty else {
            print("No benchmarks were run.")
            return
        }

        print("")
        print("fixture    median scan   fastest   slowest   variation   items/sec   layout   unreadable")
        for measurement in measurements {
            print(
                String(
                    format: "%-10s %10.4f s %8.4f s %8.4f s %8.1f%% %11.0f %7.3f ms %10d",
                    (measurement.name as NSString).utf8String!,
                    measurement.medianScanDuration,
                    measurement.fastestScanDuration,
                    measurement.slowestScanDuration,
                    measurement.variabilityFraction * 100,
                    measurement.itemsPerSecond,
                    measurement.medianLayoutDuration * 1_000,
                    measurement.maximumUnreadableCount
                )
            )
        }
    }
}

private final class BenchmarkCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var starts = 0

    var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    func markStartedAndWait() {
        lock.lock()
        starts += 1
        lock.unlock()
        semaphore.wait()
    }

    func releaseAll() {
        let count = max(startedCount, 1)
        for _ in 0..<count { semaphore.signal() }
    }
}
