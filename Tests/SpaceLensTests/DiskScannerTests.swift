import Foundation
import XCTest
@testable import SpaceLens

final class DiskScannerTests: XCTestCase {
    private struct StopStreaming: Error {}

    func testBulkDirectoryReaderReturnsMetadataWithoutFollowingSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBulkReader-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let file = root.appendingPathComponent("file.bin")
        let link = root.appendingPathComponent("folder-link")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 4_096).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

        let entries = try BulkDirectoryReader.contents(of: root)
        let metadataByName = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                entry.metadata.map { ($0.name, $0) }
            }
        )

        XCTAssertEqual(metadataByName["Folder"]?.kind, .directory)
        XCTAssertEqual(metadataByName["file.bin"]?.kind, .regular)
        XCTAssertGreaterThan(metadataByName["file.bin"]?.size ?? 0, 0)
        XCTAssertNotNil(metadataByName["file.bin"]?.modificationDate)
        XCTAssertEqual(metadataByName["folder-link"]?.kind, .symbolicLink)
        XCTAssertTrue(metadataByName.values.allSatisfy { $0.identity != nil })
    }

    func testBulkDirectoryReaderReusesBoundedBuffersAtSupportedSizes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBufferPool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        for bufferSize in [32, 64, 256].map({ $0 * 1024 }) {
            let pool = BulkDirectoryBufferPool(capacity: 2, bufferSize: bufferSize)
            for _ in 0..<3 {
                let entries = try BulkDirectoryReader.contents(of: root, using: pool)
                XCTAssertEqual(entries.map(\.metadata?.name), ["file.bin"])
            }
            XCTAssertEqual(pool.bufferSize, bufferSize)
            XCTAssertEqual(pool.pooledBufferCount, 1)
            XCTAssertEqual(pool.allocationCount, 1)
        }

        let boundedPool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 32 * 1024)
        boundedPool.withBuffer { _, _ in
            boundedPool.withBuffer { _, _ in
                XCTAssertEqual(boundedPool.pooledBufferCount, 1)
                XCTAssertEqual(boundedPool.allocationCount, 2)
            }
        }
        XCTAssertEqual(boundedPool.pooledBufferCount, boundedPool.capacity)
    }

    func testBulkDirectoryReaderStreamsEntriesAndStopsWithoutReadingLaterBatches() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensStreamingReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<500 {
            _ = FileManager.default.createFile(
                atPath: root.appendingPathComponent("file-\(index).bin").path,
                contents: Data([UInt8(index % 255)])
            )
        }

        let completeDiagnostics = ScanDiagnosticCounters()
        let completePool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 4 * 1024)
        var completeCount = 0
        try BulkDirectoryReader.forEachEntry(
            of: root,
            using: completePool,
            diagnostics: completeDiagnostics
        ) { _ in
            completeCount += 1
        }
        XCTAssertEqual(completeCount, 500)
        XCTAssertGreaterThan(
            completeDiagnostics.snapshot(bufferAllocations: completePool.allocationCount).syscallBatches,
            1
        )

        let stoppedDiagnostics = ScanDiagnosticCounters()
        let stoppedPool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 4 * 1024)
        var stoppedCount = 0
        XCTAssertThrowsError(
            try BulkDirectoryReader.forEachEntry(
                of: root,
                using: stoppedPool,
                diagnostics: stoppedDiagnostics
            ) { _ in
                stoppedCount += 1
                throw StopStreaming()
            }
        )
        XCTAssertEqual(stoppedCount, 1)
        XCTAssertEqual(
            stoppedDiagnostics.snapshot(bufferAllocations: stoppedPool.allocationCount).syscallBatches,
            1
        )
    }

    func testScannerBuildsSortedTreeAndDoesNotFollowSymbolicLinks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 0x41, count: 128 * 1024)
            .write(to: nested.appendingPathComponent("large.bin"))
        try Data(repeating: 0x42, count: 4 * 1024)
            .write(to: root.appendingPathComponent("small.bin"))
        try FileManager.default.createSymbolicLink(
            at: nested.appendingPathComponent("loop"),
            withDestinationURL: root
        )

        let result = try await DiskScanner().scan(url: root)

        XCTAssertEqual(result.root.name, root.lastPathComponent)
        XCTAssertEqual(result.root.children.count, 2)
        XCTAssertEqual(result.root.children.first?.name, "Nested")
        XCTAssertGreaterThan(result.root.size, 0)

        let symlink = result.root.children
            .first(where: { $0.name == "Nested" })?
            .children
            .first(where: { $0.name == "loop" })
        XCTAssertNotNil(symlink)
        XCTAssertFalse(symlink?.isDirectory ?? true)
        XCTAssertTrue(symlink?.children.isEmpty ?? false)
    }

    func testProgressReportsScannedItemCount() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<3 {
            try Data([UInt8(index)]).write(to: root.appendingPathComponent("\(index).txt"))
        }

        let recorder = ProgressRecorder()
        let result = try await DiskScanner().scan(url: root) { progress in
            recorder.record(progress)
        }

        XCTAssertEqual(result.itemsScanned, 4)
        XCTAssertEqual(recorder.latest?.itemsScanned, 4)
        XCTAssertEqual(recorder.latest?.mappedBytes, result.root.size)
        XCTAssertEqual(recorder.latest?.previewRoot?.size, result.root.size)
        XCTAssertLessThanOrEqual(
            recorder.latest?.previewRoot?.storageMetrics.nodeCount ?? Int.max,
            result.root.storageMetrics.nodeCount
        )
        XCTAssertTrue(recorder.snapshots.contains { progress in
            progress.previewRoot != nil && progress.itemsScanned < result.itemsScanned
        })
        let mappedByteSamples = recorder.snapshots.map(\.mappedBytes)
        XCTAssertEqual(mappedByteSamples, mappedByteSamples.sorted())
        XCTAssertGreaterThanOrEqual(result.diagnostics.syscallBatches, 1)
        XCTAssertEqual(result.diagnostics.bufferAllocations, 1)
        XCTAssertEqual(result.diagnostics.directoryCount, 1)
        XCTAssertEqual(result.diagnostics.retainedNodes, 3)
        XCTAssertEqual(result.diagnostics.discardedNodes, 0)
        XCTAssertGreaterThanOrEqual(result.diagnostics.progressEmissions, 2)
        XCTAssertEqual(result.diagnostics.retainedArenaNodeCount, 4)
        XCTAssertGreaterThan(result.diagnostics.arenaConstructionDurationSeconds, 0)
        XCTAssertGreaterThan(result.diagnostics.rssBeforeArenaConstructionBytes, 0)
        XCTAssertGreaterThan(result.diagnostics.rssAfterArenaConstructionBytes, 0)
    }

    func testLivePreviewGrowsBeforeCompletedTreeIsAvailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensLivePreview-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 8_192)
            .write(to: nested.appendingPathComponent("payload.bin"))

        let scanner = DiskScanner(directoryReader: { url, keys in
            if url.standardizedFileURL == nested.standardizedFileURL {
                Thread.sleep(forTimeInterval: 0.25)
            }
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: []
            )
        })
        let recorder = ProgressRecorder()
        let result = try await scanner.scan(url: root) { recorder.record($0) }

        let growingPreview = recorder.snapshots.first { progress in
            guard progress.mappedBytes > 0,
                  let nestedPreview = progress.previewRoot?.children.first(where: {
                      $0.name == "Nested"
                  }) else { return false }
            return nestedPreview.size > 0 && nestedPreview.children.isEmpty
        }
        XCTAssertNotNil(growingPreview)
        XCTAssertNotEqual(growingPreview?.previewRoot, result.root)
    }

    func testFinalProgressKeepsBoundedPreviewInsteadOfDuplicatingResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBoundedFinalPreview-\(UUID().uuidString)", isDirectory: true)
        let levelOne = root.appendingPathComponent("LevelOne", isDirectory: true)
        let levelTwo = levelOne.appendingPathComponent("LevelTwo", isDirectory: true)
        try FileManager.default.createDirectory(at: levelTwo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 4_096)
            .write(to: levelTwo.appendingPathComponent("payload.bin"))

        let recorder = ProgressRecorder()
        let result = try await DiskScanner().scan(url: root) { recorder.record($0) }
        let finalPreview = try XCTUnwrap(recorder.latest?.previewRoot)

        XCTAssertEqual(recorder.latest?.mappedBytes, result.root.size)
        XCTAssertLessThan(
            finalPreview.storageMetrics.nodeCount,
            result.root.storageMetrics.nodeCount
        )
        XCTAssertNotEqual(finalPreview, result.root)
    }

    func testLivePreviewRetainsOnlyEightRootBranches() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBoundedPreviewBranches-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<12 {
            let directory = root.appendingPathComponent("Branch-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: UInt8(index), count: 1_024)
                .write(to: directory.appendingPathComponent("payload.bin"))
        }

        let recorder = ProgressRecorder()
        _ = try await DiskScanner().scan(url: root) { recorder.record($0) }
        let finalPreview = try XCTUnwrap(recorder.latest?.previewRoot)

        XCTAssertLessThanOrEqual(finalPreview.children.count, 9)
        XCTAssertEqual(finalPreview.children.filter(\.isAggregate).count, 1)
    }

    func testDiagnosticCountersIncludeFallbackMetadataCalls() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("first.bin"))
        try Data([0x42]).write(to: root.appendingPathComponent("second.bin"))

        let scanner = DiskScanner(directoryReader: { url, keys in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: []
            )
        })
        let result = try await scanner.scan(url: root)

        XCTAssertEqual(result.diagnostics.syscallBatches, 0)
        XCTAssertEqual(result.diagnostics.fallbackLstatCalls, 2)
        XCTAssertEqual(result.diagnostics.bufferAllocations, 0)
        XCTAssertEqual(result.diagnostics.directoryTasks, 0)
        XCTAssertEqual(result.diagnostics.directoryCount, 1)
    }

    func testProviderMatchingOnlyExaminesDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensProviderMatching-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        let file = root.appendingPathComponent("file.bin")
        let link = root.appendingPathComponent("file-link")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let probe = URLProbe()
        let scanner = DiskScanner(shouldIsolateSubtree: { url in
            probe.record(url)
            return false
        })

        _ = try await scanner.scan(url: root)

        XCTAssertEqual(
            Set(probe.recordedPaths),
            Set([root.standardizedFileURL.path, nested.path])
        )
    }

    func testCancellationStopsDetachedScannerWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        let gate = CancellationGate()
        let traversalBudget = ScanTraversalBudget(permitCount: 2)
        let scanTask = Task {
            try await DiskScanner(traversalBudget: traversalBudget).scan(url: root) { progress in
                if progress.itemsScanned == 1 {
                    gate.markStartedAndWait()
                }
            }
        }

        for _ in 0..<200 where !gate.hasStarted {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(gate.hasStarted)
        scanTask.cancel()
        gate.release()

        do {
            _ = try await scanTask.value
            XCTFail("Cancelled scan completed successfully")
        } catch ScanFailure.cancelled {
            // Expected.
        }
        XCTAssertEqual(traversalBudget.snapshot.activeReaders, 0)
    }

    func testLargeDirectoryUsesBoundedResultTree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBoundedTree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<150 {
            try Data([UInt8(index % 255)])
                .write(to: root.appendingPathComponent("file-\(index).bin"))
        }

        let result = try await DiskScanner().scan(url: root)
        XCTAssertLessThanOrEqual(result.root.children.count, 97)
        XCTAssertTrue(result.root.children.contains(where: { $0.name == "Smaller items" }))
        XCTAssertEqual(result.itemsScanned, 151)
        XCTAssertEqual(result.root.itemCount, 151)
        XCTAssertEqual(result.root.directItemCount, 150)
        XCTAssertEqual(result.diagnostics.retainedNodes, DiskScanner.retainedChildLimit)
        XCTAssertEqual(result.diagnostics.discardedNodes, 150 - DiskScanner.retainedChildLimit)
        XCTAssertLessThan(result.diagnostics.progressMerges, result.itemsScanned / 4)
        XCTAssertEqual(result.root.children.reduce(Int64(0), { $0 + $1.size }), result.root.size)

        let retainedNodeCount = countRetainedNodes(in: result.root)
        XCTAssertEqual(result.root.storageMetrics.nodeCount, retainedNodeCount)
        XCTAssertEqual(result.root.storageMetrics.storedAbsolutePathCount, 1)
        XCTAssertLessThan(
            result.root.storageMetrics.childIndexArrayCount,
            result.root.storageMetrics.nodeCount
        )
        let retainedFile = try XCTUnwrap(result.root.children.first { !$0.isAggregate })
        XCTAssertEqual(
            retainedFile.url,
            root.appendingPathComponent(retainedFile.name).standardizedFileURL
        )
    }

    private func countRetainedNodes(in node: FileNode) -> Int {
        1 + node.children.reduce(0) { $0 + countRetainedNodes(in: $1) }
    }

    func testScanScopeRejectsDuplicateAndNestedVolumes() {
        let rootScope = ScanScope(rootPath: "/", rootDevice: 10, excludedPaths: [])
        XCTAssertTrue(
            rootScope.allows(
                path: "/Users/me",
                identity: FileIdentity(device: 10, inode: 2)
            )
        )
        XCTAssertFalse(
            rootScope.allows(
                path: "/System/Volumes/Data",
                identity: FileIdentity(device: 10, inode: 3)
            )
        )
        XCTAssertFalse(
            rootScope.allows(
                path: "/Volumes/External",
                identity: FileIdentity(device: 11, inode: 4)
            )
        )

        let folderScope = ScanScope(rootPath: "/tmp/example", rootDevice: 10, excludedPaths: [])
        XCTAssertFalse(
            folderScope.allows(
                path: "/tmp/example/mount",
                identity: FileIdentity(device: 11, inode: 5)
            )
        )

        let profilingScope = ScanScope(
            rootPath: "/",
            rootDevice: 10,
            excludedPaths: ["/Users/me/profile.trace"]
        )
        XCTAssertFalse(
            profilingScope.allows(
                path: "/Users/me/profile.trace/run/data",
                identity: FileIdentity(device: 10, inode: 6)
            )
        )
    }

    func testStalledProviderSubtreeIsSkipped() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensStallWatchdog-\(UUID().uuidString)", isDirectory: true)
        let blocked = root.appendingPathComponent("Blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = CancellationGate()
        let itemRecorder = ScannedItemRecorder()
        let traversalBudget = ScanTraversalBudget(permitCount: 2)
        let scanner = DiskScanner(
            stalledSubtreeTimeout: 0.1,
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
            traversalBudget: traversalBudget
        )

        let start = Date()
        let result = try await scanner.scan(
            url: root,
            onItem: { itemRecorder.record($0) }
        )
        let duration = Date().timeIntervalSince(start)
        let observedCountAtTimeout = itemRecorder.items.count
        gate.release()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(gate.hasStarted)
        XCTAssertLessThan(duration, 1)
        XCTAssertEqual(result.itemsScanned, 2)
        XCTAssertEqual(result.unreadableItems, 1)
        XCTAssertEqual(result.diagnostics.directoryCount, 2)
        XCTAssertEqual(result.diagnostics.providerTimeouts, 1)
        XCTAssertEqual(result.diagnostics.abandonedWorkers, 1)
        XCTAssertEqual(itemRecorder.items.count, observedCountAtTimeout)
        XCTAssertEqual(traversalBudget.snapshot.activeReaders, 0)
        XCTAssertEqual(
            result.root.children.first(where: { $0.name == "Blocked" })?.isReadable,
            false
        )
    }

    func testSiblingDirectoriesAreReadInParallel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensParallelScan-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let probe = ParallelReadProbe()
        let scanner = DiskScanner(
            maximumParallelism: 2,
            shouldIsolateSubtree: { _ in false },
            directoryReader: { url, keys in
                if url.standardizedFileURL.path == first.path
                    || url.standardizedFileURL.path == second.path {
                    probe.enterAndWaitForOverlap()
                }
                return try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            }
        )

        _ = try await scanner.scan(url: root)
        XCTAssertGreaterThanOrEqual(probe.maximumConcurrentReads, 2)
    }

    func testMultipleScannersShareOneTraversalBudget() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensSharedBudget-\(UUID().uuidString)", isDirectory: true)
        let firstRoot = fixtureRoot.appendingPathComponent("FirstRoot", isDirectory: true)
        let secondRoot = fixtureRoot.appendingPathComponent("SecondRoot", isDirectory: true)
        for root in [firstRoot, secondRoot] {
            for index in 0..<4 {
                let directory = root.appendingPathComponent("Branch\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data([UInt8(index)]).write(to: directory.appendingPathComponent("payload.bin"))
            }
        }
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let budget = ScanTraversalBudget(permitCount: 3)
        let scanner = DiskScanner(
            maximumParallelism: 3,
            shouldIsolateSubtree: { _ in false },
            directoryReader: { url, keys in
                if url.path != firstRoot.path, url.path != secondRoot.path {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                return try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            },
            traversalBudget: budget
        )

        async let first = scanner.scan(url: firstRoot)
        async let second = scanner.scan(url: secondRoot)
        let (firstResult, secondResult) = try await (first, second)
        let snapshot = budget.snapshot

        XCTAssertEqual(firstResult.itemsScanned, 9)
        XCTAssertEqual(secondResult.itemsScanned, 9)
        XCTAssertLessThanOrEqual(snapshot.maximumObservedReaders, 3)
        XCTAssertEqual(snapshot.activeReaders, 0)
        XCTAssertEqual(snapshot.waitingRootReaders, 0)
    }

    func testSinglePermitBudgetContinuesTraversalInline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensInlineBudget-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested/Leaf", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([0x41]).write(to: nested.appendingPathComponent("payload.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let budget = ScanTraversalBudget(permitCount: 1)
        let result = try await DiskScanner(
            maximumParallelism: 1,
            traversalBudget: budget
        ).scan(url: root)
        let snapshot = budget.snapshot

        XCTAssertEqual(result.itemsScanned, 4)
        XCTAssertEqual(snapshot.maximumObservedReaders, 1)
        XCTAssertEqual(snapshot.activeReaders, 0)
    }

    func testDirectoryDiscoveryPrunesArtifactsAndReportsBudgetLimits() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensDirectoryDiscovery-\(UUID().uuidString)", isDirectory: true)
        let modules = root.appendingPathComponent("node_modules", isDirectory: true)
        let source = root.appendingPathComponent("Sources/Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dependency = modules.appendingPathComponent("dependency.bin")
        let nestedSource = source.appendingPathComponent("source.swift")
        try Data(repeating: 0x41, count: 1_024).write(to: dependency)
        try Data(repeating: 0x42, count: 1_024).write(to: nestedSource)

        let artifactRecorder = ScannedItemRecorder()
        let artifactResult = try await DiskScanner().scanForDirectories(
            url: root,
            pruningDirectoryNames: ["node_modules"],
            onItem: { artifactRecorder.record($0) }
        )
        let artifactPaths = Set(artifactRecorder.items.map { $0.url.path })
        XCTAssertTrue(artifactPaths.contains(modules.path))
        XCTAssertFalse(artifactPaths.contains(dependency.path))
        XCTAssertTrue(artifactPaths.contains(nestedSource.path))
        XCTAssertFalse(artifactResult.wasTruncated)

        let budgetRecorder = ScannedItemRecorder()
        let budgetResult = try await DiskScanner().scanForDirectories(
            url: root,
            pruningDirectoryNames: [],
            budget: DirectoryDiscoveryBudget(maximumDepth: 1, maximumDirectories: 100, maximumDuration: 5),
            onItem: { budgetRecorder.record($0) }
        )
        XCTAssertTrue(budgetResult.wasTruncated)
        XCTAssertFalse(Set(budgetRecorder.items.map { $0.url.path }).contains(nestedSource.path))
    }
}

private final class ScannedItemRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ScannedFileItem] = []

    var items: [ScannedFileItem] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func record(_ item: ScannedFileItem) {
        lock.lock()
        values.append(item)
        lock.unlock()
    }
}

private final class CancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation = DispatchSemaphore(value: 0)
    private var started = false

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func markStartedAndWait() {
        lock.lock()
        started = true
        lock.unlock()
        continuation.wait()
    }

    func release() {
        continuation.signal()
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ScanProgress?
    private var values: [ScanProgress] = []

    var latest: ScanProgress? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    var snapshots: [ScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func record(_ progress: ScanProgress) {
        lock.lock()
        value = progress
        values.append(progress)
        lock.unlock()
    }
}

private final class ParallelReadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let overlapReached = DispatchSemaphore(value: 0)
    private var activeReads = 0
    private var maximumReads = 0

    var maximumConcurrentReads: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumReads
    }

    func enterAndWaitForOverlap() {
        lock.lock()
        activeReads += 1
        maximumReads = max(maximumReads, activeReads)
        if activeReads >= 2 {
            overlapReached.signal()
            overlapReached.signal()
        }
        lock.unlock()

        _ = overlapReached.wait(timeout: .now() + .milliseconds(500))

        lock.lock()
        activeReads -= 1
        lock.unlock()
    }
}

private final class URLProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    var recordedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func record(_ url: URL) {
        lock.lock()
        paths.append(url.path)
        lock.unlock()
    }
}
