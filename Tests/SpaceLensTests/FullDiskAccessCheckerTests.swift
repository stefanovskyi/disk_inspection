import Foundation
import XCTest
@testable import SpaceLens

final class FullDiskAccessCheckerTests: XCTestCase {
    func testWholeDiskScanNeedsApprovalWhenProtectedProbeFails() {
        let checker = FullDiskAccessChecker(accessProbe: { false })

        XCTAssertEqual(
            checker.status(for: URL(fileURLWithPath: "/")),
            .needsUserApproval
        )
    }

    func testWholeDiskScanContinuesWhenProtectedProbeSucceeds() {
        let checker = FullDiskAccessChecker(accessProbe: { true })

        XCTAssertEqual(checker.status(for: URL(fileURLWithPath: "/")), .granted)
    }

    func testFolderScanDoesNotRequireFullDiskAccess() {
        let checker = FullDiskAccessChecker(accessProbe: { false })

        XCTAssertEqual(
            checker.status(for: URL(fileURLWithPath: "/Users/example/Documents")),
            .notRequired
        )
    }
}
