import Foundation
import XCTest
@testable import SpaceLens

final class ScanSessionStoreTests: XCTestCase {
    func testResultsAreRetainedPerVolumeAndReplacedByRescan() {
        let firstURL = URL(fileURLWithPath: "/Volumes/First")
        let secondURL = URL(fileURLWithPath: "/Volumes/Second")
        let firstResult = result(name: "First", size: 100, url: firstURL)
        let refreshedResult = result(name: "First", size: 120, url: firstURL)
        let secondResult = result(name: "Second", size: 40, url: secondURL)
        var store = ScanSessionStore()

        XCTAssertNil(store.result(for: firstURL))

        store.store(firstResult, for: firstURL)
        store.store(secondResult, for: secondURL)
        store.store(refreshedResult, for: firstURL)

        XCTAssertEqual(store.result(for: firstURL), refreshedResult)
        XCTAssertEqual(store.result(for: secondURL), secondResult)

        store.removeResult(for: firstURL)

        XCTAssertNil(store.result(for: firstURL))
        XCTAssertEqual(store.result(for: secondURL), secondResult)
    }

    private func result(name: String, size: Int64, url: URL) -> ScanResult {
        ScanResult(
            root: FileNode(
                url: url,
                name: name,
                size: size,
                isDirectory: true,
                isReadable: true,
                children: []
            ),
            duration: 1,
            itemsScanned: 1,
            unreadableItems: 0
        )
    }
}
