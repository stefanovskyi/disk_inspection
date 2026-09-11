import XCTest
@testable import SpaceLens

final class AppLayoutMetricsTests: XCTestCase {
    func testSidebarAndWindowDimensionsRemainStable() {
        XCTAssertEqual(AppLayoutMetrics.sidebarWidth, 248)
        XCTAssertEqual(AppLayoutMetrics.minimumWindowWidth, 1_100)
        XCTAssertEqual(AppLayoutMetrics.minimumWindowHeight, 620)
    }

    func testInspectorAndToolsColumnsUseCompactWidths() {
        XCTAssertEqual(AppLayoutMetrics.preferredInspectorWidth, 240)
        XCTAssertEqual(AppLayoutMetrics.toolsColumnWidth, 250)
    }
}
