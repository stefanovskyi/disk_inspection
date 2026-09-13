import Darwin
import Foundation

private struct BenchmarkSystemReport: Codable {
    let operatingSystem: String
    let hardwareModel: String
    let processorDescription: String
    let processorCount: Int
    let activeProcessorCount: Int
    let physicalMemoryBytes: UInt64
}

private struct BenchmarkConfigurationReport: Codable {
    let iterations: Int
    let selectedFixtures: [String]
    let scannerParallelism: Int
    let volumeScanLimit: Int
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

private struct BenchmarkIterationReport: Codable {
    let iteration: Int
    let scanDurationSeconds: Double
    let itemsScanned: Int
    let directoryCount: Int
    let itemsPerSecond: Double
    let unreadableItems: Int
    let layoutDurationMilliseconds: Double
    let cachedHoverLookup120Milliseconds: Double
    let segmentCount: Int
    let syscallBatches: Int
    let fallbackLstatCalls: Int
    let bufferAllocations: Int
    let directoryTasks: Int
    let retainedNodes: Int
    let discardedNodes: Int
    let progressMerges: Int
    let progressEmissions: Int
    let progressLockAcquisitions: Int
    let progressLockWaitNanoseconds: UInt64
    let progressLockHoldNanoseconds: UInt64
    let previewMappedByteMerges: Int
    let rootPreviewBranchResolutions: Int
    let completedPreviewAttempts: Int
    let completedPreviewAccepted: Int
    let previewConstructions: Int
    let previewEmissions: Int
    let workerProgressFlushes: Int
    let forcedProgressFlushes: Int
    let providerTimeouts: Int
    let abandonedWorkers: Int
    let retainedArenaNodeCount: Int
    let arenaConstructionDurationMilliseconds: Double
    let rssBeforeArenaConstructionBytes: UInt64
    let rssAfterArenaConstructionBytes: UInt64
    let maximumDirectoryReaders: Int?
    let cancellationLatencyMilliseconds: Double?
}

private struct BenchmarkSummaryReport: Codable {
    let medianScanDurationSeconds: Double
    let fastestScanDurationSeconds: Double
    let slowestScanDurationSeconds: Double
    let meanScanDurationSeconds: Double
    let scanDurationStandardDeviationSeconds: Double
    let variabilityPercent: Double
    let itemsPerSecond: Double
    let medianLayoutDurationMilliseconds: Double
    let medianCachedHoverLookup120Milliseconds: Double
    let medianSegmentCount: Int
    let maximumUnreadableItems: Int
    let maximumDirectoryReaders: Int?
    let medianCancellationLatencyMilliseconds: Double?
}

private struct BenchmarkFixtureReport: Codable {
    let name: String
    let summary: BenchmarkSummaryReport
    let iterations: [BenchmarkIterationReport]
}

private struct BenchmarkTraceReport: Codable {
    let requested: Bool
    let template: String?
    let path: String?
}

private struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let runID: String
    let startedAt: Date
    let finishedAt: Date
    let gitRevision: String
    let gitDirty: Bool
    let sdkPath: String
    let swiftVersion: String
    let buildOptimization: String
    let peakResidentMemoryBytes: UInt64
    let system: BenchmarkSystemReport
    let configuration: BenchmarkConfigurationReport
    let trace: BenchmarkTraceReport
    let fixtures: [BenchmarkFixtureReport]
}

enum BenchmarkReportWriter {
    static func write(
        configuration: BenchmarkConfiguration,
        measurements: [BenchmarkMeasurement],
        startedAt: Date,
        finishedAt: Date
    ) throws -> (json: URL, csv: URL) {
        let outputDirectory = configuration.outputDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let report = makeReport(
            configuration: configuration,
            measurements: measurements,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        let baseName = "spacelens-benchmark-\(configuration.runID)"
        let jsonURL = outputDirectory.appendingPathComponent("\(baseName).json")
        let csvURL = outputDirectory.appendingPathComponent("\(baseName).csv")
        guard !FileManager.default.fileExists(atPath: jsonURL.path),
              !FileManager.default.fileExists(atPath: csvURL.path) else {
            throw BenchmarkFailure.invalidConfiguration(
                "Benchmark report already exists for run ID \(configuration.runID)"
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: jsonURL, options: .atomic)
        try csvData(for: report).write(to: csvURL, options: .atomic)
        return (jsonURL, csvURL)
    }

    private static func makeReport(
        configuration: BenchmarkConfiguration,
        measurements: [BenchmarkMeasurement],
        startedAt: Date,
        finishedAt: Date
    ) -> BenchmarkReport {
        let processInfo = ProcessInfo.processInfo
        return BenchmarkReport(
            schemaVersion: 6,
            runID: configuration.runID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            gitRevision: configuration.gitRevision,
            gitDirty: configuration.gitDirty,
            sdkPath: configuration.sdkPath,
            swiftVersion: configuration.swiftVersion,
            buildOptimization: "-O -whole-module-optimization",
            peakResidentMemoryBytes: peakResidentMemoryBytes(),
            system: BenchmarkSystemReport(
                operatingSystem: processInfo.operatingSystemVersionString,
                hardwareModel: systemValue(named: "hw.model") ?? "unknown",
                processorDescription: systemValue(named: "machdep.cpu.brand_string") ?? "unknown",
                processorCount: processInfo.processorCount,
                activeProcessorCount: processInfo.activeProcessorCount,
                physicalMemoryBytes: processInfo.physicalMemory
            ),
            configuration: BenchmarkConfigurationReport(
                iterations: configuration.iterations,
                selectedFixtures: configuration.selectedFixtures.sorted(),
                scannerParallelism: configuration.scannerParallelism,
                volumeScanLimit: configuration.volumeScanLimit,
                directoryBufferSizeBytes: configuration.directoryBufferSize,
                flatFileCount: configuration.flatFileCount,
                deepDirectoryCount: configuration.deepDirectoryCount,
                mixedDepth: configuration.mixedDepth,
                mixedFanout: configuration.mixedFanout,
                mixedFilesPerDirectory: configuration.mixedFilesPerDirectory,
                providerTimeoutMilliseconds: Int(configuration.providerTimeout * 1_000),
                externalPathWasProvided: configuration.externalPath != nil,
                fullDiskAccessGranted: configuration.fullDiskAccessGranted
            ),
            trace: BenchmarkTraceReport(
                requested: configuration.tracePath != nil,
                template: configuration.traceTemplate,
                path: configuration.tracePath
            ),
            fixtures: measurements.map(fixtureReport)
        )
    }

    private static func fixtureReport(_ measurement: BenchmarkMeasurement) -> BenchmarkFixtureReport {
        let iterationReports = measurement.scanDurations.indices.map { index in
            let scanDuration = measurement.scanDurations[index]
            let itemCount = measurement.itemCounts[index]
            let diagnostics = measurement.diagnostics[index]
            return BenchmarkIterationReport(
                iteration: index + 1,
                scanDurationSeconds: scanDuration,
                itemsScanned: itemCount,
                directoryCount: diagnostics.directoryCount,
                itemsPerSecond: scanDuration > 0 ? Double(itemCount) / scanDuration : 0,
                unreadableItems: measurement.unreadableCounts[index],
                layoutDurationMilliseconds: measurement.layoutDurations[index] * 1_000,
                cachedHoverLookup120Milliseconds: measurement.cachedHoverDurations[index] * 1_000,
                segmentCount: measurement.segmentCounts[index],
                syscallBatches: diagnostics.syscallBatches,
                fallbackLstatCalls: diagnostics.fallbackLstatCalls,
                bufferAllocations: diagnostics.bufferAllocations,
                directoryTasks: diagnostics.directoryTasks,
                retainedNodes: diagnostics.retainedNodes,
                discardedNodes: diagnostics.discardedNodes,
                progressMerges: diagnostics.progressMerges,
                progressEmissions: diagnostics.progressEmissions,
                progressLockAcquisitions: diagnostics.progressLockAcquisitions,
                progressLockWaitNanoseconds: diagnostics.progressLockWaitNanoseconds,
                progressLockHoldNanoseconds: diagnostics.progressLockHoldNanoseconds,
                previewMappedByteMerges: diagnostics.previewMappedByteMerges,
                rootPreviewBranchResolutions: diagnostics.rootPreviewBranchResolutions,
                completedPreviewAttempts: diagnostics.completedPreviewAttempts,
                completedPreviewAccepted: diagnostics.completedPreviewAccepted,
                previewConstructions: diagnostics.previewConstructions,
                previewEmissions: diagnostics.previewEmissions,
                workerProgressFlushes: diagnostics.workerProgressFlushes,
                forcedProgressFlushes: diagnostics.forcedProgressFlushes,
                providerTimeouts: diagnostics.providerTimeouts,
                abandonedWorkers: diagnostics.abandonedWorkers,
                retainedArenaNodeCount: diagnostics.retainedArenaNodeCount,
                arenaConstructionDurationMilliseconds: diagnostics.arenaConstructionDurationSeconds * 1_000,
                rssBeforeArenaConstructionBytes: diagnostics.rssBeforeArenaConstructionBytes,
                rssAfterArenaConstructionBytes: diagnostics.rssAfterArenaConstructionBytes,
                maximumDirectoryReaders: measurement.maximumDirectoryReaderCounts[index],
                cancellationLatencyMilliseconds: measurement.cancellationLatencies[index].map {
                    $0 * 1_000
                }
            )
        }

        return BenchmarkFixtureReport(
            name: measurement.name,
            summary: BenchmarkSummaryReport(
                medianScanDurationSeconds: measurement.medianScanDuration,
                fastestScanDurationSeconds: measurement.fastestScanDuration,
                slowestScanDurationSeconds: measurement.slowestScanDuration,
                meanScanDurationSeconds: measurement.meanScanDuration,
                scanDurationStandardDeviationSeconds: measurement.scanDurationStandardDeviation,
                variabilityPercent: measurement.variabilityFraction * 100,
                itemsPerSecond: measurement.itemsPerSecond,
                medianLayoutDurationMilliseconds: measurement.medianLayoutDuration * 1_000,
                medianCachedHoverLookup120Milliseconds: measurement.medianCachedHoverDuration * 1_000,
                medianSegmentCount: measurement.medianSegmentCount,
                maximumUnreadableItems: measurement.maximumUnreadableCount,
                maximumDirectoryReaders: measurement.maximumDirectoryReaderCount,
                medianCancellationLatencyMilliseconds: measurement.medianCancellationLatency.map {
                    $0 * 1_000
                }
            ),
            iterations: iterationReports
        )
    }

    private static func csvData(for report: BenchmarkReport) -> Data {
        let header = [
            "schema_version", "run_id", "started_at", "git_revision", "git_dirty",
            "operating_system", "hardware_model", "active_processor_count",
            "physical_memory_bytes", "peak_resident_memory_bytes", "scanner_parallelism",
            "volume_scan_limit",
            "directory_buffer_size_bytes", "fixture", "iteration", "scan_seconds",
            "items_scanned", "directory_count", "items_per_second",
            "unreadable_items", "layout_milliseconds",
            "cached_hover_lookup_120_milliseconds", "segment_count",
            "syscall_batches", "fallback_lstat_calls", "buffer_allocations",
            "directory_tasks", "retained_nodes", "discarded_nodes",
            "progress_merges", "progress_emissions", "progress_lock_acquisitions",
            "progress_lock_wait_nanoseconds", "progress_lock_hold_nanoseconds",
            "preview_mapped_byte_merges", "root_preview_branch_resolutions",
            "completed_preview_attempts", "completed_preview_accepted",
            "preview_constructions", "preview_emissions", "worker_progress_flushes",
            "forced_progress_flushes", "provider_timeouts",
            "abandoned_workers", "retained_arena_node_count",
            "arena_construction_milliseconds", "rss_before_arena_construction_bytes",
            "rss_after_arena_construction_bytes", "maximum_directory_readers",
            "cancellation_latency_milliseconds"
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows = [header.map(csvField).joined(separator: ",")]

        for fixture in report.fixtures {
            for iteration in fixture.iterations {
                var values: [String] = [
                    String(report.schemaVersion),
                    report.runID,
                    formatter.string(from: report.startedAt),
                    report.gitRevision,
                    String(report.gitDirty),
                    report.system.operatingSystem,
                    report.system.hardwareModel,
                    String(report.system.activeProcessorCount),
                    String(report.system.physicalMemoryBytes),
                    String(report.peakResidentMemoryBytes),
                    String(report.configuration.scannerParallelism),
                    String(report.configuration.volumeScanLimit),
                    String(report.configuration.directoryBufferSizeBytes),
                    fixture.name,
                    String(iteration.iteration),
                    String(format: "%.9f", iteration.scanDurationSeconds),
                    String(iteration.itemsScanned),
                    String(iteration.directoryCount),
                    String(format: "%.3f", iteration.itemsPerSecond),
                    String(iteration.unreadableItems),
                    String(format: "%.6f", iteration.layoutDurationMilliseconds),
                    String(format: "%.6f", iteration.cachedHoverLookup120Milliseconds),
                    String(iteration.segmentCount)
                ]
                let traversalDiagnosticValues = [
                    String(iteration.syscallBatches),
                    String(iteration.fallbackLstatCalls),
                    String(iteration.bufferAllocations),
                    String(iteration.directoryTasks),
                    String(iteration.retainedNodes),
                    String(iteration.discardedNodes),
                ]
                let progressDiagnosticValues = [
                    String(iteration.progressMerges),
                    String(iteration.progressEmissions),
                    String(iteration.progressLockAcquisitions),
                    String(iteration.progressLockWaitNanoseconds),
                    String(iteration.progressLockHoldNanoseconds),
                    String(iteration.previewMappedByteMerges),
                    String(iteration.rootPreviewBranchResolutions),
                    String(iteration.completedPreviewAttempts),
                    String(iteration.completedPreviewAccepted),
                    String(iteration.previewConstructions),
                    String(iteration.previewEmissions),
                    String(iteration.workerProgressFlushes),
                    String(iteration.forcedProgressFlushes),
                ]
                let completionDiagnosticValues = [
                    String(iteration.providerTimeouts),
                    String(iteration.abandonedWorkers),
                    String(iteration.retainedArenaNodeCount),
                    String(format: "%.6f", iteration.arenaConstructionDurationMilliseconds),
                    String(iteration.rssBeforeArenaConstructionBytes),
                    String(iteration.rssAfterArenaConstructionBytes)
                ]
                values.append(contentsOf: traversalDiagnosticValues)
                values.append(contentsOf: progressDiagnosticValues)
                values.append(contentsOf: completionDiagnosticValues)
                values.append(iteration.maximumDirectoryReaders.map(String.init) ?? "")
                values.append(
                    iteration.cancellationLatencyMilliseconds.map {
                        String(format: "%.6f", $0)
                    } ?? ""
                )
                rows.append(values.map(csvField).joined(separator: ","))
            }
        }

        return Data((rows.joined(separator: "\n") + "\n").utf8)
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func peakResidentMemoryBytes() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(usage.ru_maxrss, 0))
    }

    private static func systemValue(named name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}
