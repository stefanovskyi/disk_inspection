import Foundation

struct BenchmarkComparisonThresholds: Codable, Equatable {
    let scanPercent: Double
    let layoutPercent: Double
    let memoryPercent: Double

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        Self(
            scanPercent: try percentage(
                named: "SPACELENS_BENCHMARK_SCAN_REGRESSION_THRESHOLD_PERCENT",
                default: 10,
                environment: environment
            ),
            layoutPercent: try percentage(
                named: "SPACELENS_BENCHMARK_LAYOUT_REGRESSION_THRESHOLD_PERCENT",
                default: 10,
                environment: environment
            ),
            memoryPercent: try percentage(
                named: "SPACELENS_BENCHMARK_MEMORY_REGRESSION_THRESHOLD_PERCENT",
                default: 10,
                environment: environment
            )
        )
    }

    private static func percentage(
        named name: String,
        default defaultValue: Double,
        environment: [String: String]
    ) throws -> Double {
        guard let rawValue = environment[name] else { return defaultValue }
        guard let value = Double(rawValue), value.isFinite, value >= 0 else {
            throw BenchmarkComparisonError.invalidInput("\(name) must be a finite, non-negative number")
        }
        return value
    }
}

struct BenchmarkComparisonReport: Codable {
    struct ReportIdentity: Codable {
        let path: String
        let runID: String
        let gitRevision: String
        let gitDirty: Bool
    }

    struct Metric: Codable {
        let baseline: Double
        let candidate: Double
        let deltaPercent: Double?
        let regressionThresholdPercent: Double?
        let regression: Bool
    }

    struct Fixture: Codable {
        let name: String
        let medianScanDurationSeconds: Metric
        let itemsPerSecond: Metric
        let medianLayoutDurationMilliseconds: Metric
        let medianItemsScanned: Metric?
        let maximumUnreadableItemsBaseline: Int
        let maximumUnreadableItemsCandidate: Int
        let diagnostics: Diagnostics?
    }

    struct Diagnostics: Codable {
        let directoryCount: Metric
        let syscallBatches: Metric
        let fallbackLstatCalls: Metric
        let bufferAllocations: Metric
        let directoryTasks: Metric
        let retainedNodes: Metric
        let discardedNodes: Metric
        let progressMerges: Metric
        let progressEmissions: Metric
        let providerTimeouts: Metric
        let abandonedWorkers: Metric
        let retainedArenaNodeCount: Metric
        let arenaConstructionDurationMilliseconds: Metric
        let rssBeforeArenaConstructionBytes: Metric
        let rssAfterArenaConstructionBytes: Metric
    }

    let schemaVersion: Int
    let createdAt: Date
    let baseline: ReportIdentity
    let candidate: ReportIdentity
    let thresholds: BenchmarkComparisonThresholds
    let configurationCompatible: Bool
    let configurationDifferences: [String]
    let peakResidentMemoryBytes: Metric
    let fixtures: [Fixture]
    let regressions: [String]
    let passed: Bool
}

enum BenchmarkComparisonError: LocalizedError {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        }
    }
}

private struct BenchmarkInputReport: Decodable {
    struct System: Decodable {
        let operatingSystem: String
        let hardwareModel: String
        let activeProcessorCount: Int
    }

    struct Configuration: Decodable {
        let iterations: Int
        let selectedFixtures: [String]
        let scannerParallelism: Int
        let volumeScanLimit: Int?
        let directoryBufferSizeBytes: Int
        let flatFileCount: Int
        let deepDirectoryCount: Int
        let mixedDepth: Int
        let mixedFanout: Int
        let mixedFilesPerDirectory: Int
        let providerTimeoutMilliseconds: Int
        let externalPathWasProvided: Bool
        let fullDiskAccessGranted: Bool?
    }

    struct Summary: Decodable {
        let medianScanDurationSeconds: Double
        let itemsPerSecond: Double
        let medianLayoutDurationMilliseconds: Double
        let maximumUnreadableItems: Int
    }

    struct Fixture: Decodable {
        struct Iteration: Decodable {
            let itemsScanned: Int?
            let directoryCount: Int?
            let syscallBatches: Int?
            let fallbackLstatCalls: Int?
            let bufferAllocations: Int?
            let directoryTasks: Int?
            let retainedNodes: Int?
            let discardedNodes: Int?
            let progressMerges: Int?
            let progressEmissions: Int?
            let providerTimeouts: Int?
            let abandonedWorkers: Int?
            let retainedArenaNodeCount: Int?
            let arenaConstructionDurationMilliseconds: Double?
            let rssBeforeArenaConstructionBytes: UInt64?
            let rssAfterArenaConstructionBytes: UInt64?
        }

        let name: String
        let summary: Summary
        let iterations: [Iteration]?
    }

    struct Trace: Decodable {
        let requested: Bool
        let template: String?
    }

    let schemaVersion: Int
    let runID: String
    let gitRevision: String
    let gitDirty: Bool
    let sdkPath: String
    let swiftVersion: String
    let peakResidentMemoryBytes: UInt64
    let system: System
    let configuration: Configuration
    let trace: Trace
    let fixtures: [Fixture]
}

enum BenchmarkReportComparator {
    static func compare(
        baselineURL: URL,
        candidateURL: URL,
        thresholds: BenchmarkComparisonThresholds
    ) throws -> BenchmarkComparisonReport {
        let decoder = JSONDecoder()
        let baseline = try decodeReport(at: baselineURL, using: decoder)
        let candidate = try decodeReport(at: candidateURL, using: decoder)

        let differences = configurationDifferences(baseline: baseline, candidate: candidate)
        let baselineFixtures = Dictionary(uniqueKeysWithValues: baseline.fixtures.map { ($0.name, $0) })
        let candidateFixtures = Dictionary(uniqueKeysWithValues: candidate.fixtures.map { ($0.name, $0) })
        let fixtureNames = Set(baselineFixtures.keys).intersection(candidateFixtures.keys).sorted()
        guard !fixtureNames.isEmpty else {
            throw BenchmarkComparisonError.invalidInput("Reports do not contain a common fixture")
        }

        var regressions: [String] = []
        let fixtures = fixtureNames.map { name -> BenchmarkComparisonReport.Fixture in
            let baselineFixture = baselineFixtures[name]!
            let candidateFixture = candidateFixtures[name]!
            let scan = metric(
                baseline: baselineFixture.summary.medianScanDurationSeconds,
                candidate: candidateFixture.summary.medianScanDurationSeconds,
                threshold: thresholds.scanPercent,
                lowerIsBetter: true
            )
            let throughput = metric(
                baseline: baselineFixture.summary.itemsPerSecond,
                candidate: candidateFixture.summary.itemsPerSecond,
                threshold: nil,
                lowerIsBetter: false
            )
            let layout = metric(
                baseline: baselineFixture.summary.medianLayoutDurationMilliseconds,
                candidate: candidateFixture.summary.medianLayoutDurationMilliseconds,
                threshold: thresholds.layoutPercent,
                lowerIsBetter: true
            )
            if scan.regression { regressions.append("\(name) median scan duration") }
            if layout.regression { regressions.append("\(name) median layout duration") }
            return BenchmarkComparisonReport.Fixture(
                name: name,
                medianScanDurationSeconds: scan,
                itemsPerSecond: throughput,
                medianLayoutDurationMilliseconds: layout,
                medianItemsScanned: iterationMetric(
                    baseline: baselineFixture,
                    candidate: candidateFixture,
                    value: { $0.itemsScanned.map(Double.init) }
                ),
                maximumUnreadableItemsBaseline: baselineFixture.summary.maximumUnreadableItems,
                maximumUnreadableItemsCandidate: candidateFixture.summary.maximumUnreadableItems,
                diagnostics: diagnosticComparison(
                    baseline: baselineFixture,
                    candidate: candidateFixture
                )
            )
        }

        let memory = metric(
            baseline: Double(baseline.peakResidentMemoryBytes),
            candidate: Double(candidate.peakResidentMemoryBytes),
            threshold: thresholds.memoryPercent,
            lowerIsBetter: true
        )
        if memory.regression { regressions.append("peak resident memory") }

        return BenchmarkComparisonReport(
            schemaVersion: 2,
            createdAt: Date(),
            baseline: .init(
                path: baselineURL.standardizedFileURL.path,
                runID: baseline.runID,
                gitRevision: baseline.gitRevision,
                gitDirty: baseline.gitDirty
            ),
            candidate: .init(
                path: candidateURL.standardizedFileURL.path,
                runID: candidate.runID,
                gitRevision: candidate.gitRevision,
                gitDirty: candidate.gitDirty
            ),
            thresholds: thresholds,
            configurationCompatible: differences.isEmpty,
            configurationDifferences: differences,
            peakResidentMemoryBytes: memory,
            fixtures: fixtures,
            regressions: regressions,
            passed: differences.isEmpty && regressions.isEmpty
        )
    }

    private static func decodeReport(at url: URL, using decoder: JSONDecoder) throws -> BenchmarkInputReport {
        do {
            return try decoder.decode(BenchmarkInputReport.self, from: Data(contentsOf: url))
        } catch {
            throw BenchmarkComparisonError.invalidInput("Could not decode \(url.path): \(error.localizedDescription)")
        }
    }

    private static func metric(
        baseline: Double,
        candidate: Double,
        threshold: Double?,
        lowerIsBetter: Bool
    ) -> BenchmarkComparisonReport.Metric {
        let delta = percentageDelta(baseline: baseline, candidate: candidate)
        let regressed: Bool
        if let threshold {
            if let delta {
                regressed = lowerIsBetter ? delta > threshold : delta < -threshold
            } else {
                regressed = candidate != baseline && (lowerIsBetter ? candidate > baseline : candidate < baseline)
            }
        } else {
            regressed = false
        }
        return .init(
            baseline: baseline,
            candidate: candidate,
            deltaPercent: delta,
            regressionThresholdPercent: threshold,
            regression: regressed
        )
    }

    private static func percentageDelta(baseline: Double, candidate: Double) -> Double? {
        guard baseline != 0 else { return candidate == 0 ? 0 : nil }
        return ((candidate - baseline) / baseline) * 100
    }

    private static func diagnosticComparison(
        baseline: BenchmarkInputReport.Fixture,
        candidate: BenchmarkInputReport.Fixture
    ) -> BenchmarkComparisonReport.Diagnostics? {
        func compared(
            _ value: (BenchmarkInputReport.Fixture.Iteration) -> Double?
        ) -> BenchmarkComparisonReport.Metric? {
            iterationMetric(baseline: baseline, candidate: candidate, value: value)
        }

        guard
            let directoryCount = compared({ $0.directoryCount.map(Double.init) }),
            let syscallBatches = compared({ $0.syscallBatches.map(Double.init) }),
            let fallbackLstatCalls = compared({ $0.fallbackLstatCalls.map(Double.init) }),
            let bufferAllocations = compared({ $0.bufferAllocations.map(Double.init) }),
            let directoryTasks = compared({ $0.directoryTasks.map(Double.init) }),
            let retainedNodes = compared({ $0.retainedNodes.map(Double.init) }),
            let discardedNodes = compared({ $0.discardedNodes.map(Double.init) }),
            let progressMerges = compared({ $0.progressMerges.map(Double.init) }),
            let progressEmissions = compared({ $0.progressEmissions.map(Double.init) }),
            let providerTimeouts = compared({ $0.providerTimeouts.map(Double.init) }),
            let abandonedWorkers = compared({ $0.abandonedWorkers.map(Double.init) }),
            let retainedArenaNodeCount = compared({ $0.retainedArenaNodeCount.map(Double.init) }),
            let arenaConstructionDurationMilliseconds = compared({
                $0.arenaConstructionDurationMilliseconds
            }),
            let rssBeforeArenaConstructionBytes = compared({
                $0.rssBeforeArenaConstructionBytes.map { Double($0) }
            }),
            let rssAfterArenaConstructionBytes = compared({
                $0.rssAfterArenaConstructionBytes.map { Double($0) }
            })
        else { return nil }

        return .init(
            directoryCount: directoryCount,
            syscallBatches: syscallBatches,
            fallbackLstatCalls: fallbackLstatCalls,
            bufferAllocations: bufferAllocations,
            directoryTasks: directoryTasks,
            retainedNodes: retainedNodes,
            discardedNodes: discardedNodes,
            progressMerges: progressMerges,
            progressEmissions: progressEmissions,
            providerTimeouts: providerTimeouts,
            abandonedWorkers: abandonedWorkers,
            retainedArenaNodeCount: retainedArenaNodeCount,
            arenaConstructionDurationMilliseconds: arenaConstructionDurationMilliseconds,
            rssBeforeArenaConstructionBytes: rssBeforeArenaConstructionBytes,
            rssAfterArenaConstructionBytes: rssAfterArenaConstructionBytes
        )
    }

    private static func iterationMetric(
        baseline: BenchmarkInputReport.Fixture,
        candidate: BenchmarkInputReport.Fixture,
        value: (BenchmarkInputReport.Fixture.Iteration) -> Double?
    ) -> BenchmarkComparisonReport.Metric? {
        guard let baselineIterations = baseline.iterations,
              let candidateIterations = candidate.iterations else { return nil }
        let baselineValues = baselineIterations.compactMap(value)
        let candidateValues = candidateIterations.compactMap(value)
        guard baselineValues.count == baselineIterations.count,
              candidateValues.count == candidateIterations.count,
              !baselineValues.isEmpty,
              !candidateValues.isEmpty else { return nil }
        return metric(
            baseline: median(baselineValues),
            candidate: median(candidateValues),
            threshold: nil,
            lowerIsBetter: true
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func configurationDifferences(
        baseline: BenchmarkInputReport,
        candidate: BenchmarkInputReport
    ) -> [String] {
        var differences: [String] = []
        func compare<T: Equatable>(_ name: String, _ left: T, _ right: T) {
            if left != right { differences.append("\(name): \(left) != \(right)") }
        }

        compare("operating system", baseline.system.operatingSystem, candidate.system.operatingSystem)
        compare("hardware model", baseline.system.hardwareModel, candidate.system.hardwareModel)
        compare("active processor count", baseline.system.activeProcessorCount, candidate.system.activeProcessorCount)
        compare("SDK", baseline.sdkPath, candidate.sdkPath)
        compare("Swift compiler", baseline.swiftVersion, candidate.swiftVersion)
        compare("iterations", baseline.configuration.iterations, candidate.configuration.iterations)
        compare(
            "fixtures",
            baseline.configuration.selectedFixtures.sorted(),
            candidate.configuration.selectedFixtures.sorted()
        )
        compare("scanner parallelism", baseline.configuration.scannerParallelism, candidate.configuration.scannerParallelism)
        compare(
            "directory buffer bytes",
            baseline.configuration.directoryBufferSizeBytes,
            candidate.configuration.directoryBufferSizeBytes
        )
        compare("trace capture", baseline.trace.requested, candidate.trace.requested)
        compare("trace template", baseline.trace.template, candidate.trace.template)

        let fixtures = Set(baseline.configuration.selectedFixtures).union(candidate.configuration.selectedFixtures)
        if fixtures.contains("multi-volume") {
            compare(
                "volume scan limit",
                baseline.configuration.volumeScanLimit,
                candidate.configuration.volumeScanLimit
            )
        }
        if fixtures.contains("flat") {
            compare("flat file count", baseline.configuration.flatFileCount, candidate.configuration.flatFileCount)
        }
        if fixtures.contains("deep") {
            compare("deep directory count", baseline.configuration.deepDirectoryCount, candidate.configuration.deepDirectoryCount)
        }
        if fixtures.contains("mixed") || fixtures.contains("multi-volume") {
            compare("mixed depth", baseline.configuration.mixedDepth, candidate.configuration.mixedDepth)
            compare("mixed fanout", baseline.configuration.mixedFanout, candidate.configuration.mixedFanout)
            compare(
                "mixed files per directory",
                baseline.configuration.mixedFilesPerDirectory,
                candidate.configuration.mixedFilesPerDirectory
            )
        }
        if fixtures.contains("provider") {
            compare(
                "provider timeout milliseconds",
                baseline.configuration.providerTimeoutMilliseconds,
                candidate.configuration.providerTimeoutMilliseconds
            )
        }
        if fixtures.contains("external") {
            compare(
                "external path provided",
                baseline.configuration.externalPathWasProvided,
                candidate.configuration.externalPathWasProvided
            )
        }
        if fixtures.contains("full-disk") {
            compare(
                "Full Disk Access",
                baseline.configuration.fullDiskAccessGranted,
                candidate.configuration.fullDiskAccessGranted
            )
        }
        return differences
    }
}
