import Foundation

@main
struct BenchmarkComparisonTests {
    static func main() throws {
        try testPercentageDeltasAndThresholds()
        try testConfigurationMismatchFailsComparison()
        try testLegacyReportsRemainComparable()
        try testThresholdValidation()
        print("Benchmark comparison tests passed")
    }

    private static func testPercentageDeltasAndThresholds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensComparisonTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = directory.appendingPathComponent("baseline.json")
        let candidate = directory.appendingPathComponent("candidate.json")
        try report(scan: 10, throughput: 100, layout: 4, memory: 1_000, parallelism: 8).write(to: baseline)
        try report(scan: 11.1, throughput: 90, layout: 4.2, memory: 1_050, parallelism: 8).write(to: candidate)

        let comparison = try BenchmarkReportComparator.compare(
            baselineURL: baseline,
            candidateURL: candidate,
            thresholds: .init(scanPercent: 10, layoutPercent: 10, memoryPercent: 10)
        )
        try expect(comparison.configurationCompatible, "identical configurations were rejected")
        try expect(comparison.fixtures.count == 1, "matching fixture was not compared")
        try expect(comparison.fixtures[0].medianScanDurationSeconds.regression, "scan regression was missed")
        try expect(!comparison.fixtures[0].medianLayoutDurationMilliseconds.regression, "layout threshold was misapplied")
        try expect(!comparison.peakResidentMemoryBytes.regression, "memory threshold was misapplied")
        try expect(comparison.fixtures[0].itemsPerSecond.deltaPercent == -10, "throughput delta is incorrect")
        try expect(comparison.fixtures[0].medianItemsScanned != nil, "item counts were not compared")
        try expect(comparison.fixtures[0].diagnostics != nil, "scanner diagnostics were not compared")
        try expect(
            comparison.fixtures[0].diagnostics?.retainedArenaNodeCount.baseline == 700,
            "retained arena node count is incorrect"
        )
        try expect(
            comparison.fixtures[0].diagnostics?.rssBeforeArenaConstructionBytes.baseline == 1_000_000,
            "arena RSS boundary is incorrect"
        )
        try expect(!comparison.passed, "regressed comparison unexpectedly passed")
    }

    private static func testConfigurationMismatchFailsComparison() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensComparisonTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = directory.appendingPathComponent("baseline.json")
        let candidate = directory.appendingPathComponent("candidate.json")
        try report(scan: 10, throughput: 100, layout: 4, memory: 1_000, parallelism: 8).write(to: baseline)
        try report(scan: 9, throughput: 110, layout: 3, memory: 900, parallelism: 4).write(to: candidate)

        let comparison = try BenchmarkReportComparator.compare(
            baselineURL: baseline,
            candidateURL: candidate,
            thresholds: .init(scanPercent: 10, layoutPercent: 10, memoryPercent: 10)
        )
        try expect(!comparison.configurationCompatible, "parallelism mismatch was not detected")
        try expect(
            comparison.configurationDifferences.contains { $0.contains("scanner parallelism") },
            "parallelism mismatch was not explained"
        )
        try expect(!comparison.passed, "configuration mismatch unexpectedly passed")
    }

    private static func testThresholdValidation() throws {
        do {
            _ = try BenchmarkComparisonThresholds.load(environment: [
                "SPACELENS_BENCHMARK_SCAN_REGRESSION_THRESHOLD_PERCENT": "-1"
            ])
            throw TestFailure(message: "negative threshold was accepted")
        } catch is BenchmarkComparisonError {
            // Expected.
        }
    }

    private static func testLegacyReportsRemainComparable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensLegacyComparisonTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = directory.appendingPathComponent("baseline.json")
        let candidate = directory.appendingPathComponent("candidate.json")
        try report(
            scan: 10,
            throughput: 100,
            layout: 4,
            memory: 1_000,
            parallelism: 8,
            includeDiagnostics: false
        ).write(to: baseline)
        try report(scan: 9, throughput: 110, layout: 3, memory: 900, parallelism: 8).write(to: candidate)

        let comparison = try BenchmarkReportComparator.compare(
            baselineURL: baseline,
            candidateURL: candidate,
            thresholds: .init(scanPercent: 10, layoutPercent: 10, memoryPercent: 10)
        )
        try expect(comparison.configurationCompatible, "additive schema change rejected a legacy report")
        try expect(comparison.fixtures[0].diagnostics == nil, "legacy diagnostics were fabricated")
    }

    private static func report(
        scan: Double,
        throughput: Double,
        layout: Double,
        memory: UInt64,
        parallelism: Int,
        includeDiagnostics: Bool = true
    ) throws -> Data {
        var fixture: [String: Any] = [
            "name": "flat",
            "summary": [
                "medianScanDurationSeconds": scan,
                "itemsPerSecond": throughput,
                "medianLayoutDurationMilliseconds": layout,
                "maximumUnreadableItems": 0
            ]
        ]
        if includeDiagnostics {
            fixture["iterations"] = [[
                "itemsScanned": 1_000,
                "directoryCount": 100,
                "syscallBatches": 40,
                "fallbackLstatCalls": 0,
                "bufferAllocations": 8,
                "directoryTasks": 80,
                "retainedNodes": 700,
                "discardedNodes": 300,
                "progressMerges": 120,
                "progressEmissions": 10,
                "providerTimeouts": 1,
                "abandonedWorkers": 1,
                "retainedArenaNodeCount": 700,
                "arenaConstructionDurationMilliseconds": 2.5,
                "rssBeforeArenaConstructionBytes": 1_000_000,
                "rssAfterArenaConstructionBytes": 1_100_000
            ]]
        }
        let object: [String: Any] = [
            "schemaVersion": includeDiagnostics ? 3 : 2,
            "runID": "test-run",
            "gitRevision": "c30bd8336fe9d4a267adbd307c3071aee1752ec9",
            "gitDirty": false,
            "sdkPath": "/SDK",
            "swiftVersion": "Swift test",
            "peakResidentMemoryBytes": memory,
            "system": [
                "operatingSystem": "macOS Test",
                "hardwareModel": "TestMac",
                "activeProcessorCount": 8
            ],
            "configuration": [
                "iterations": 9,
                "selectedFixtures": ["flat"],
                "scannerParallelism": parallelism,
                "directoryBufferSizeBytes": 65_536,
                "flatFileCount": 12_000,
                "deepDirectoryCount": 96,
                "mixedDepth": 3,
                "mixedFanout": 6,
                "mixedFilesPerDirectory": 12,
                "providerTimeoutMilliseconds": 75,
                "externalPathWasProvided": false,
                "fullDiskAccessGranted": NSNull()
            ],
            "trace": ["requested": false, "template": NSNull()],
            "fixtures": [fixture]
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message: message) }
    }
}

private struct TestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
