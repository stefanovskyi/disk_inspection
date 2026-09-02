import Foundation

enum SelfTestFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

private struct StopDirectoryStreaming: Error {}

@main
struct SpaceLensSelfTests {
    static func main() async throws {
        try await scannerBuildsTreeWithoutFollowingSymlinks()
        try await diagnosticCountersTrackScannerWork()
        try await providerMatchingOnlyExaminesDirectories()
        try bulkDirectoryReaderReturnsMetadataWithoutFollowingSymlinks()
        try bulkDirectoryReaderReusesBoundedBuffersAtSupportedSizes()
        try bulkDirectoryReaderStreamsAndStopsEarly()
        try await largeDirectoriesKeepABoundedResultTree()
        try await cancellationStopsTheScannerWorker()
        try await stalledProviderSubtreeIsSkipped()
        try await scannerReadsSiblingDirectoriesInParallel()
        try fullDiskAccessIsCheckedOnlyForWholeDiskScans()
        try elapsedTimeFormattingIsReadable()
        try scanScopeStaysInsideTheSelectedVolume()
        try layoutPreservesHierarchyAndProportion()
        try layoutLeavesRequestedFreeSpaceOpen()
        try layoutRespectsDepthLimit()
        try sessionStoreRetainsAndReplacesVolumeResults()
        print("SpaceLens self-tests passed (17/17)")
    }

    private static func scannerBuildsTreeWithoutFollowingSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensSelfTests-\(UUID().uuidString)", isDirectory: true)
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
        try expect(result.root.children.count == 2, "Scanner did not build the expected root children")
        try expect(result.root.children.first?.name == "Nested", "Scanner did not sort children by size")

        let symlink = result.root.children
            .first(where: { $0.name == "Nested" })?
            .children
            .first(where: { $0.name == "loop" })
        try expect(symlink != nil, "Scanner omitted the symbolic link entry")
        try expect(symlink?.isDirectory == false, "Scanner followed a symbolic link as a directory")
        try expect(symlink?.children.isEmpty == true, "Symbolic link unexpectedly has descendants")
    }

    private static func bulkDirectoryReaderReturnsMetadataWithoutFollowingSymlinks() throws {
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

        try expect(metadataByName["Folder"]?.kind == .directory, "Bulk reader lost directory metadata")
        try expect(metadataByName["file.bin"]?.kind == .regular, "Bulk reader lost regular-file metadata")
        try expect((metadataByName["file.bin"]?.size ?? 0) > 0, "Bulk reader lost allocated file size")
        try expect(metadataByName["folder-link"]?.kind == .symbolicLink, "Bulk reader followed a symbolic link")
        try expect(metadataByName.values.allSatisfy { $0.identity != nil }, "Bulk reader lost device/inode identities")
    }

    private static func diagnosticCountersTrackScannerWork() async throws {
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

        try expect(result.diagnostics.syscallBatches == 0, "Custom reader recorded bulk syscall batches")
        try expect(result.diagnostics.fallbackLstatCalls == 2, "Fallback lstat calls were not counted")
        try expect(result.diagnostics.bufferAllocations == 0, "Custom reader allocated a bulk buffer")
        try expect(result.diagnostics.directoryTasks == 0, "Flat scan created a directory task")
        try expect(result.diagnostics.retainedNodes == 2, "Retained node decisions were not counted")
        try expect(result.diagnostics.discardedNodes == 0, "Flat scan discarded a node")
        try expect(result.diagnostics.progressEmissions >= 2, "Progress emissions were not counted")
    }

    private static func providerMatchingOnlyExaminesDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensProviderMatching-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        let file = root.appendingPathComponent("file.bin")
        let link = root.appendingPathComponent("file-link")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let probe = ProviderMatchingProbe()
        let scanner = DiskScanner(shouldIsolateSubtree: { url in
            probe.record(url)
            return false
        })
        _ = try await scanner.scan(url: root)

        try expect(
            Set(probe.recordedPaths) == Set([root.standardizedFileURL.path, nested.path]),
            "Provider matching examined a regular file or symbolic link"
        )
    }

    private static func bulkDirectoryReaderReusesBoundedBuffersAtSupportedSizes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBufferPool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        for bufferSize in [32, 64, 256].map({ $0 * 1024 }) {
            let pool = BulkDirectoryBufferPool(capacity: 2, bufferSize: bufferSize)
            for _ in 0..<3 {
                let entries = try BulkDirectoryReader.contents(of: root, using: pool)
                try expect(
                    entries.compactMap(\.metadata?.name) == ["file.bin"],
                    "Bulk reader changed results at \(bufferSize / 1024) KB"
                )
            }
            try expect(pool.bufferSize == bufferSize, "Bulk reader changed the configured buffer size")
            try expect(pool.pooledBufferCount == 1, "Bulk reader did not reuse its pooled buffer")
            try expect(pool.allocationCount == 1, "Bulk reader allocated a buffer per directory read")
        }

        let boundedPool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 32 * 1024)
        boundedPool.withBuffer { _, _ in
            boundedPool.withBuffer { _, _ in
                // The second concurrent lease is deliberately unpooled so a
                // timed-out provider syscall cannot block unrelated reads.
            }
        }
        try expect(
            boundedPool.pooledBufferCount == boundedPool.capacity,
            "Bulk reader retained more buffers than its configured capacity"
        )
    }

    private static func bulkDirectoryReaderStreamsAndStopsEarly() throws {
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
        try expect(completeCount == 500, "Streaming reader omitted directory entries")
        try expect(
            completeDiagnostics.snapshot(bufferAllocations: completePool.allocationCount).syscallBatches > 1,
            "Streaming fixture did not span multiple kernel batches"
        )

        let stoppedDiagnostics = ScanDiagnosticCounters()
        let stoppedPool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 4 * 1024)
        var stoppedCount = 0
        do {
            try BulkDirectoryReader.forEachEntry(
                of: root,
                using: stoppedPool,
                diagnostics: stoppedDiagnostics
            ) { _ in
                stoppedCount += 1
                throw StopDirectoryStreaming()
            }
            throw SelfTestFailure.failed("Streaming reader ignored callback termination")
        } catch is StopDirectoryStreaming {
            // Expected.
        }
        try expect(stoppedCount == 1, "Streaming reader materialized entries before callback delivery")
        try expect(
            stoppedDiagnostics.snapshot(bufferAllocations: stoppedPool.allocationCount).syscallBatches == 1,
            "Streaming reader fetched a later batch after callback termination"
        )
    }

    private static func layoutPreservesHierarchyAndProportion() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let deep = node("deep", size: 25, at: rootURL.appendingPathComponent("large/deep"))
        let large = node("large", size: 75, at: rootURL.appendingPathComponent("large"), children: [deep])
        let small = node("small", size: 25, at: rootURL.appendingPathComponent("small"))
        let root = node("test", size: 100, at: rootURL, children: [large, small])
        let segments = SunburstLayout.segments(for: root, maxDepth: 4, minimumAngularSpan: 0)

        guard let largeSegment = segments.first(where: { $0.node.name == "large" }),
              let smallSegment = segments.first(where: { $0.node.name == "small" }),
              let deepSegment = segments.first(where: { $0.node.name == "deep" }) else {
            throw SelfTestFailure.failed("Layout omitted expected segments")
        }

        try expect(deepSegment.depth == 1, "Layout lost the child depth")
        let ratio = largeSegment.angularSpan / smallSegment.angularSpan
        try expect(abs(ratio - 3) < 0.001, "Layout angles are not proportional to byte size")
    }

    private static func layoutLeavesRequestedFreeSpaceOpen() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let first = node("first", size: 60, at: rootURL.appendingPathComponent("first"))
        let second = node("second", size: 40, at: rootURL.appendingPathComponent("second"))
        let root = node("test", size: 100, at: rootURL, children: [first, second])
        let segments = SunburstLayout.segments(
            for: root,
            maxDepth: 2,
            minimumAngularSpan: 0,
            angularExtent: .pi * 1.5
        )

        let furthestAngle = segments.map(\.endAngle).max() ?? 0
        try expect(
            abs(furthestAngle - (.pi * 1.5)) < 0.001,
            "Layout filled the free-space sector instead of leaving it open"
        )
    }

    private static func cancellationStopsTheScannerWorker() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        let gate = CancellationTestGate()
        let scanTask = Task {
            try await DiskScanner().scan(url: root) { progress in
                if progress.itemsScanned == 1 {
                    gate.markStartedAndWait()
                }
            }
        }

        for _ in 0..<200 where !gate.hasStarted {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard gate.hasStarted else {
            scanTask.cancel()
            gate.release()
            throw SelfTestFailure.failed("Scanner worker did not start")
        }

        scanTask.cancel()
        gate.release()

        do {
            _ = try await scanTask.value
            throw SelfTestFailure.failed("Cancelled scan completed successfully instead of stopping")
        } catch ScanFailure.cancelled {
            // Expected.
        }
    }

    private static func largeDirectoriesKeepABoundedResultTree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBoundedTree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<150 {
            try Data([UInt8(index % 255)])
                .write(to: root.appendingPathComponent("file-\(index).bin"))
        }

        let result = try await DiskScanner().scan(url: root)
        try expect(result.root.children.count <= 97, "Scanner retained every file in a large directory")
        try expect(
            result.root.children.contains(where: { $0.name == "Smaller items" }),
            "Scanner did not aggregate smaller items"
        )
        try expect(result.itemsScanned == 151, "Scanner lost the real measured-item count")
        try expect(result.root.itemCount == 151, "Compacted tree lost its represented-item count")
        try expect(result.root.directItemCount == 150, "Compacted tree lost its direct-item count")
        try expect(
            result.diagnostics.progressMerges < result.itemsScanned / 4,
            "Progress totals were merged once per scanned item instead of in batches"
        )
        try expect(
            result.root.children.reduce(Int64(0), { $0 + $1.size }) == result.root.size,
            "Aggregating smaller items changed the measured byte total"
        )
        func countRetainedNodes(in node: FileNode) -> Int {
            1 + node.children.reduce(0) { $0 + countRetainedNodes(in: $1) }
        }
        try expect(
            result.root.storageMetrics.storedAbsolutePathCount == 1,
            "Retained result stored more than one absolute path"
        )
        try expect(
            result.root.storageMetrics.nodeCount == countRetainedNodes(in: result.root),
            "Compact result arena did not contain exactly the retained nodes"
        )
    }

    private static func stalledProviderSubtreeIsSkipped() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensStallWatchdog-\(UUID().uuidString)", isDirectory: true)
        let blocked = root.appendingPathComponent("Blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = CancellationTestGate()
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
            }
        )

        let start = Date()
        let result = try await scanner.scan(url: root)
        let duration = Date().timeIntervalSince(start)
        gate.release()

        try expect(gate.hasStarted, "Stall watchdog fixture never entered the blocked subtree")
        try expect(duration < 1, "Stalled subtree blocked the whole scan for \(duration) seconds")
        try expect(result.itemsScanned == 2, "Stalled subtree changed precise item accounting")
        try expect(result.unreadableItems == 1, "Stalled subtree was not counted as unreadable")
        try expect(
            result.root.children.first(where: { $0.name == "Blocked" })?.isReadable == false,
            "Stalled subtree was not represented as unreadable"
        )
    }

    private static func scannerReadsSiblingDirectoriesInParallel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensParallelScan-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let probe = ParallelDirectoryReadProbe()
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
        try expect(
            probe.maximumConcurrentReads >= 2,
            "Scanner reached only \(probe.maximumConcurrentReads) concurrent sibling directory read(s)"
        )
    }

    private static func scanScopeStaysInsideTheSelectedVolume() throws {
        let rootScope = ScanScope(rootPath: "/", rootDevice: 10, excludedPaths: [])
        try expect(
            rootScope.allows(path: "/Users/me", identity: FileIdentity(device: 10, inode: 2)),
            "Root scope rejected a logical main-disk folder"
        )
        try expect(
            !rootScope.allows(path: "/System/Volumes/Data", identity: FileIdentity(device: 10, inode: 3)),
            "Root scope allowed the duplicate APFS Data mount"
        )
        try expect(
            !rootScope.allows(path: "/Volumes/External", identity: FileIdentity(device: 11, inode: 4)),
            "Root scope crossed into an external disk"
        )

        let folderScope = ScanScope(rootPath: "/tmp/example", rootDevice: 10, excludedPaths: [])
        try expect(
            !folderScope.allows(path: "/tmp/example/mount", identity: FileIdentity(device: 11, inode: 5)),
            "Folder scope crossed a nested volume boundary"
        )
        let profilingScope = ScanScope(
            rootPath: "/",
            rootDevice: 10,
            excludedPaths: ["/Users/me/profile.trace"]
        )
        try expect(
            !profilingScope.allows(
                path: "/Users/me/profile.trace/run/data",
                identity: FileIdentity(device: 10, inode: 6)
            ),
            "Full-disk profiling recursed into its active trace bundle"
        )
    }

    private static func fullDiskAccessIsCheckedOnlyForWholeDiskScans() throws {
        let denied = FullDiskAccessChecker(accessProbe: { false })
        let granted = FullDiskAccessChecker(accessProbe: { true })

        try expect(
            denied.status(for: URL(fileURLWithPath: "/")) == .needsUserApproval,
            "Whole-disk scan did not request Full Disk Access"
        )
        try expect(
            granted.status(for: URL(fileURLWithPath: "/")) == .granted,
            "Whole-disk scan ignored available Full Disk Access"
        )
        try expect(
            denied.status(for: URL(fileURLWithPath: "/Users/example/Documents")) == .notRequired,
            "Folder scan unnecessarily requested Full Disk Access"
        )
    }

    private static func elapsedTimeFormattingIsReadable() throws {
        try expect(
            StorageFormatters.duration(65) == "1 min 5 sec",
            "Elapsed scan time was not formatted as minutes and seconds"
        )
    }

    private static func layoutRespectsDepthLimit() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let third = node("three", size: 1, at: rootURL.appendingPathComponent("one/two/three"))
        let second = node("two", size: 1, at: rootURL.appendingPathComponent("one/two"), children: [third])
        let first = node("one", size: 1, at: rootURL.appendingPathComponent("one"), children: [second])
        let root = node("test", size: 1, at: rootURL, children: [first])
        let segments = SunburstLayout.segments(for: root, maxDepth: 2, minimumAngularSpan: 0)
        try expect(segments.map(\.depth).max() == 1, "Layout exceeded its configured depth")
    }

    private static func sessionStoreRetainsAndReplacesVolumeResults() throws {
        let firstURL = URL(fileURLWithPath: "/Volumes/First")
        let secondURL = URL(fileURLWithPath: "/Volumes/Second")
        let firstResult = ScanResult(
            root: node("First", size: 100, at: firstURL),
            duration: 2,
            itemsScanned: 5,
            unreadableItems: 0
        )
        let refreshedResult = ScanResult(
            root: node("First", size: 120, at: firstURL),
            duration: 1,
            itemsScanned: 6,
            unreadableItems: 0
        )
        let secondResult = ScanResult(
            root: node("Second", size: 40, at: secondURL),
            duration: 1,
            itemsScanned: 2,
            unreadableItems: 0
        )
        var store = ScanSessionStore()

        try expect(store.result(for: firstURL) == nil, "An unscanned disk unexpectedly had cached data")
        store.store(firstResult, for: firstURL)
        store.store(secondResult, for: secondURL)
        store.store(refreshedResult, for: firstURL)

        try expect(store.result(for: firstURL) == refreshedResult, "A rescan did not replace the cached disk result")
        try expect(store.result(for: secondURL) == secondResult, "Rescanning one disk discarded another cached result")

        store.removeResult(for: firstURL)
        try expect(store.result(for: firstURL) == nil, "Removing a session location kept its cached result")
        try expect(store.result(for: secondURL) == secondResult, "Removing one session location discarded another result")
    }

    private static func node(
        _ name: String,
        size: Int64,
        at url: URL,
        children: [FileNode] = []
    ) -> FileNode {
        FileNode(
            url: url,
            name: name,
            size: size,
            isDirectory: !children.isEmpty,
            isReadable: true,
            children: children
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestFailure.failed(message) }
    }
}

private final class CancellationTestGate: @unchecked Sendable {
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

private final class ParallelDirectoryReadProbe: @unchecked Sendable {
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

private final class ProviderMatchingProbe: @unchecked Sendable {
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
