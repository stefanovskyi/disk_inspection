import Foundation
import XCTest
@testable import SpaceLens

final class PreviousScanStoreTests: XCTestCase {
    func testSummaryRoundTripsUsingStableVolumeIdentifier() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensPreviousScan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PreviousScanStore(fileURL: directory.appendingPathComponent("summary.json"))
        let volume = makeVolume(uuid: "TEST-VOLUME")
        let result = makeResult(childCount: 3)
        let scannedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = PreviousScanSummary(result: result, volume: volume, scannedAt: scannedAt)

        try store.store(summary)

        XCTAssertEqual(store.load()[volume.persistentIdentifier], summary)
        let restoredRoot = try XCTUnwrap(store.load()[volume.persistentIdentifier]?.makeRoot(at: volume.url))
        XCTAssertEqual(restoredRoot.url, volume.url.standardizedFileURL)
        XCTAssertEqual(restoredRoot.size, result.root.size)
        XCTAssertEqual(restoredRoot.children.map(\.name), result.root.sortedChildren.map(\.name))

        let restoredResult = try XCTUnwrap(store.load()[volume.persistentIdentifier]?.makeResult(at: volume.url))
        XCTAssertEqual(restoredResult.root.url, restoredRoot.url)
        XCTAssertEqual(restoredResult.root.size, restoredRoot.size)
        XCTAssertEqual(restoredResult.root.children.map(\.name), restoredRoot.children.map(\.name))
        XCTAssertEqual(restoredResult.duration, result.duration)
        XCTAssertEqual(restoredResult.itemsScanned, result.itemsScanned)
        XCTAssertEqual(restoredResult.unreadableItems, result.unreadableItems)
    }

    func testSummaryRetainsAllScannerChildren() throws {
        let volume = makeVolume(uuid: nil)
        let result = makeResult(childCount: 12)
        let summary = PreviousScanSummary(result: result, volume: volume)
        let root = summary.makeRoot(at: volume.url)

        XCTAssertEqual(root.children.count, 12)
        XCTAssertEqual(root.children.filter(\.isAggregate).count, 0)
        XCTAssertEqual(root.children.reduce(Int64(0)) { $0 + $1.size }, result.root.size)
        XCTAssertEqual(summary.volumeIdentifier, "path:/Volumes/Test")
    }

    func testSummaryRetainsEveryLevelVisibleInTheChart() throws {
        let volume = makeVolume(uuid: "VISIBLE-DEPTH")
        let rootURL = volume.url
        var descendant = FileNode(
            url: rootURL.appendingPathComponent("Level-7"),
            name: "Level-7",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: []
        )
        for level in stride(from: 6, through: 1, by: -1) {
            descendant = FileNode(
                url: rootURL.appendingPathComponent("Level-\(level)"),
                name: "Level-\(level)",
                size: 1,
                isDirectory: true,
                isReadable: true,
                children: [descendant]
            )
        }
        let result = ScanResult(
            root: FileNode(
                url: rootURL,
                name: "Test",
                size: 1,
                isDirectory: true,
                isReadable: true,
                children: [descendant]
            ),
            duration: 1,
            itemsScanned: 8,
            unreadableItems: 0
        )

        let restoredRoot = PreviousScanSummary(result: result, volume: volume).makeRoot(at: rootURL)
        var restored = restoredRoot
        for level in 1...6 {
            restored = try XCTUnwrap(restored.children.first, "Missing chart level \(level)")
        }
        XCTAssertEqual(restored.name, "Level-6")
    }

    func testCorruptArchiveLoadsAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensPreviousScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiveURL = directory.appendingPathComponent("summary.json")
        try Data("not-json".utf8).write(to: archiveURL)

        XCTAssertTrue(PreviousScanStore(fileURL: archiveURL).load().isEmpty)
    }

    private func makeVolume(uuid: String?) -> VolumeInfo {
        VolumeInfo(
            url: URL(fileURLWithPath: "/Volumes/Test", isDirectory: true),
            name: "Test",
            totalCapacity: 1_000,
            availableCapacity: 200,
            isExternal: true,
            isReadOnly: false,
            uuid: uuid
        )
    }

    private func makeResult(childCount: Int) -> ScanResult {
        let rootURL = URL(fileURLWithPath: "/Volumes/Test", isDirectory: true)
        let children = (0..<childCount).map { index in
            FileNode(
                url: rootURL.appendingPathComponent("Folder-\(index)"),
                name: "Folder-\(index)",
                size: Int64(index + 1),
                isDirectory: true,
                isReadable: true,
                children: [],
                itemCount: index + 1
            )
        }
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        let root = FileNode(
            url: rootURL,
            name: "Test",
            size: total,
            isDirectory: true,
            isReadable: true,
            children: children,
            itemCount: children.reduce(1) { $0 + $1.itemCount }
        )
        return ScanResult(
            root: root,
            duration: 2.5,
            itemsScanned: root.itemCount,
            unreadableItems: 0
        )
    }
}
