import Foundation
import XCTest
@testable import SpaceLens

final class DiskScannerTests: XCTestCase {
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
    }

    func testCancellationStopsDetachedScannerWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        let gate = CancellationGate()
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
        XCTAssertTrue(gate.hasStarted)
        scanTask.cancel()
        gate.release()

        do {
            _ = try await scanTask.value
            XCTFail("Cancelled scan completed successfully")
        } catch ScanFailure.cancelled {
            // Expected.
        }
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
        XCTAssertEqual(result.root.children.reduce(Int64(0), { $0 + $1.size }), result.root.size)
    }

    func testScanScopeRejectsDuplicateAndNestedVolumes() {
        let rootScope = ScanScope(rootPath: "/", rootDevice: 10)
        XCTAssertTrue(
            rootScope.allows(
                URL(fileURLWithPath: "/Users/me"),
                identity: FileIdentity(device: 10, inode: 2)
            )
        )
        XCTAssertFalse(
            rootScope.allows(
                URL(fileURLWithPath: "/System/Volumes/Data"),
                identity: FileIdentity(device: 10, inode: 3)
            )
        )
        XCTAssertFalse(
            rootScope.allows(
                URL(fileURLWithPath: "/Volumes/External"),
                identity: FileIdentity(device: 11, inode: 4)
            )
        )

        let folderScope = ScanScope(rootPath: "/tmp/example", rootDevice: 10)
        XCTAssertFalse(
            folderScope.allows(
                URL(fileURLWithPath: "/tmp/example/mount"),
                identity: FileIdentity(device: 11, inode: 5)
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

        XCTAssertTrue(gate.hasStarted)
        XCTAssertLessThan(duration, 1)
        XCTAssertEqual(result.unreadableItems, 1)
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

    var latest: ScanProgress? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record(_ progress: ScanProgress) {
        lock.lock()
        value = progress
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
