import Foundation

@main
struct CompareBenchmarks {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3 else {
            throw BenchmarkComparisonError.invalidInput(
                "Usage: compare_benchmarks.sh BASELINE.json CANDIDATE.json OUTPUT.json"
            )
        }

        let baselineURL = URL(fileURLWithPath: arguments[0])
        let candidateURL = URL(fileURLWithPath: arguments[1])
        let outputURL = URL(fileURLWithPath: arguments[2])
        let thresholds = try BenchmarkComparisonThresholds.load()
        let report = try BenchmarkReportComparator.compare(
            baselineURL: baselineURL,
            candidateURL: candidateURL,
            thresholds: thresholds
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: outputURL, options: .atomic)
        printReport(report, outputURL: outputURL)

        if !report.configurationCompatible {
            Foundation.exit(2)
        }
        if !report.regressions.isEmpty {
            Foundation.exit(1)
        }
    }

    private static func printReport(_ report: BenchmarkComparisonReport, outputURL: URL) {
        print("SpaceLens benchmark comparison")
        print("Baseline:  \(report.baseline.runID) (\(shortRevision(report.baseline.gitRevision)))")
        print("Candidate: \(report.candidate.runID) (\(shortRevision(report.candidate.gitRevision)))")
        print(
            String(
                format: "Thresholds: scan %.1f%%, layout %.1f%%, memory %.1f%%",
                report.thresholds.scanPercent,
                report.thresholds.layoutPercent,
                report.thresholds.memoryPercent
            )
        )

        if !report.configurationDifferences.isEmpty {
            print("Configuration mismatch:")
            for difference in report.configurationDifferences { print("  - \(difference)") }
        }

        print("")
        print("fixture      scan delta   throughput delta   layout delta       items   unreadable")
        for fixture in report.fixtures {
            let unreadable = "\(fixture.maximumUnreadableItemsBaseline) -> \(fixture.maximumUnreadableItemsCandidate)"
            let scanDelta = formattedDelta(fixture.medianScanDurationSeconds)
            let throughputDelta = formattedDelta(fixture.itemsPerSecond)
            let layoutDelta = formattedDelta(fixture.medianLayoutDurationMilliseconds)
            let items = fixture.medianItemsScanned.map(formattedIntegerPair) ?? "n/a"
            print(
                String(
                    format: "%-12s %10s %17s %14s %11s %12s",
                    (fixture.name as NSString).utf8String!,
                    (scanDelta as NSString).utf8String!,
                    (throughputDelta as NSString).utf8String!,
                    (layoutDelta as NSString).utf8String!,
                    (items as NSString).utf8String!,
                    (unreadable as NSString).utf8String!
                )
            )
            printDiagnostics(fixture.diagnostics)
        }
        let memoryDelta = formattedDelta(report.peakResidentMemoryBytes)
        print(
            String(
                format: "Peak RSS: %.1f MiB -> %.1f MiB (%s)",
                report.peakResidentMemoryBytes.baseline / 1_048_576,
                report.peakResidentMemoryBytes.candidate / 1_048_576,
                (memoryDelta as NSString).utf8String!
            )
        )
        print("Result: \(report.passed ? "PASS" : "FAIL")")
        if !report.regressions.isEmpty { print("Regressions: \(report.regressions.joined(separator: ", "))") }
        print("Comparison JSON: \(outputURL.standardizedFileURL.path)")
    }

    private static func formattedDelta(_ metric: BenchmarkComparisonReport.Metric) -> String {
        let suffix = metric.regression ? " FAIL" : ""
        guard let delta = metric.deltaPercent else { return "n/a\(suffix)" }
        return String(format: "%+.1f%%", delta) + suffix
    }

    private static func printDiagnostics(_ diagnostics: BenchmarkComparisonReport.Diagnostics?) {
        guard let diagnostics else {
            print("  diagnostics: unavailable in one or both reports")
            return
        }
        print(
            "  traversal: directories \(formattedIntegerPair(diagnostics.directoryCount)), "
                + "batches \(formattedIntegerPair(diagnostics.syscallBatches)), "
                + "fallback-lstat \(formattedIntegerPair(diagnostics.fallbackLstatCalls)), "
                + "buffers \(formattedIntegerPair(diagnostics.bufferAllocations)), "
                + "tasks \(formattedIntegerPair(diagnostics.directoryTasks))"
        )
        print(
            "  nodes: retained \(formattedIntegerPair(diagnostics.retainedNodes)), "
                + "discarded \(formattedIntegerPair(diagnostics.discardedNodes)), "
                + "arena \(formattedIntegerPair(diagnostics.retainedArenaNodeCount))"
        )
        print(
            "  progress: merges \(formattedIntegerPair(diagnostics.progressMerges)), "
                + "emissions \(formattedIntegerPair(diagnostics.progressEmissions)); "
                + "providers: timeouts \(formattedIntegerPair(diagnostics.providerTimeouts)), "
                + "abandoned \(formattedIntegerPair(diagnostics.abandonedWorkers))"
        )
        if let progressLocks = diagnostics.progressLockAcquisitions,
           let workerFlushes = diagnostics.workerProgressFlushes,
           let forcedFlushes = diagnostics.forcedProgressFlushes {
            print(
                "  progress coordination: locks \(formattedIntegerPair(progressLocks)), "
                    + "worker flushes \(formattedIntegerPair(workerFlushes)), "
                    + "forced flushes \(formattedIntegerPair(forcedFlushes))"
            )
        }
        if let byteMerges = diagnostics.previewMappedByteMerges,
           let branchResolutions = diagnostics.rootPreviewBranchResolutions,
           let completionAttempts = diagnostics.completedPreviewAttempts,
           let previewConstructions = diagnostics.previewConstructions,
           let previewEmissions = diagnostics.previewEmissions {
            print(
                "  preview: byte merges \(formattedIntegerPair(byteMerges)), "
                    + "branch resolutions \(formattedIntegerPair(branchResolutions)), "
                    + "completion attempts \(formattedIntegerPair(completionAttempts)), "
                    + "constructions \(formattedIntegerPair(previewConstructions)), "
                    + "emissions \(formattedIntegerPair(previewEmissions))"
            )
        }
        if let wait = diagnostics.progressLockWaitNanoseconds,
           let hold = diagnostics.progressLockHoldNanoseconds {
            print(
                "  progress lock: wait \(formattedNanosecondPair(wait)), "
                    + "hold \(formattedNanosecondPair(hold))"
            )
        }
        print(
            "  arena: \(formattedDecimalPair(diagnostics.arenaConstructionDurationMilliseconds, suffix: " ms")), "
                + "RSS before \(formattedMemoryPair(diagnostics.rssBeforeArenaConstructionBytes)), "
                + "after \(formattedMemoryPair(diagnostics.rssAfterArenaConstructionBytes))"
        )
    }

    private static func formattedIntegerPair(_ metric: BenchmarkComparisonReport.Metric) -> String {
        String(format: "%.0f -> %.0f", metric.baseline, metric.candidate)
    }

    private static func formattedDecimalPair(
        _ metric: BenchmarkComparisonReport.Metric,
        suffix: String
    ) -> String {
        String(format: "%.3f -> %.3f", metric.baseline, metric.candidate) + suffix
    }

    private static func formattedMemoryPair(_ metric: BenchmarkComparisonReport.Metric) -> String {
        String(
            format: "%.1f -> %.1f MiB",
            metric.baseline / 1_048_576,
            metric.candidate / 1_048_576
        )
    }

    private static func formattedNanosecondPair(
        _ metric: BenchmarkComparisonReport.Metric
    ) -> String {
        String(
            format: "%.3f -> %.3f ms",
            metric.baseline / 1_000_000,
            metric.candidate / 1_000_000
        )
    }

    private static func shortRevision(_ revision: String) -> String {
        String(revision.prefix(8))
    }
}
