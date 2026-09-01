import XCTest
@testable import SpaceLens

final class StorageFormattersTests: XCTestCase {
    func testDurationUsesMinutesAndSeconds() {
        XCTAssertEqual(StorageFormatters.duration(65), "1 min 5 sec")
    }
}
