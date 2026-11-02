import XCTest
@testable import SpaceLens

final class StorageItemDescriptionTests: XCTestCase {
    private func safety(_ path: String, isDirectory: Bool = true) -> StorageItemDescription.Safety? {
        StorageItemDescription.resolve(url: URL(fileURLWithPath: path), isDirectory: isDirectory)?.safety
    }

    func testKnownLocationsAreDescribedOnAnyMac() {
        XCTAssertEqual(safety("/"), .keep)
        XCTAssertEqual(safety("/Users/anyone/.ssh"), .keep)
        XCTAssertEqual(safety("/Users/anyone/Library/Caches"), .safeToClear)
        XCTAssertEqual(safety("/Users/anyone/Library/Caches/com.example.app"), .safeToClear)
        XCTAssertEqual(safety("/Users/anyone/Library/Containers/com.example.app"), .reviewFirst)
    }

    func testFirmlinksAndRootSymlinksShareTheirCanonicalDescription() {
        XCTAssertEqual(safety("/System/Volumes/Data/Users/anyone/.npm"), safety("/Users/anyone/.npm"))
        XCTAssertEqual(safety("/var/folders"), safety("/private/var/folders"))
    }

    func testSameNamesOutsideKnownLocationsStayUndescribed() {
        XCTAssertNil(safety("/work/Library/Caches"))
        XCTAssertNil(safety("/Users/anyone/projects/Documents"))
        XCTAssertNil(safety("/Users/Shared/Library"))
        XCTAssertNil(safety("/work/node_modules", isDirectory: false))
    }

    func testEveryDescriptionIsShortAndComplete() {
        for description in StorageItemDescriptionCatalog.all {
            XCTAssertLessThanOrEqual(description.text.count, 200, description.text)
            XCTAssertTrue(description.text.hasSuffix("."), description.text)
        }
    }
}
