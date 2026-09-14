import Foundation
import XCTest
@testable import SpaceLens

final class FullDiskAccessCheckerTests: XCTestCase {
    func testDefaultProbeTargetsCurrentUsersProtectedDatabase() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        XCTAssertEqual(
            FullDiskAccessChecker.protectedDatabaseURL(homeDirectory: homeDirectory).path,
            "/Users/example/Library/Application Support/com.apple.TCC/TCC.db"
        )
    }

    func testStatusRerunsProbeBeforeEveryActivity() {
        let probe = SequencedAccessProbe([false, true, false])
        let checker = FullDiskAccessChecker(accessProbe: { probe.next() })

        XCTAssertEqual(checker.status(), .needsUserApproval)
        XCTAssertEqual(checker.status(), .granted)
        XCTAssertEqual(checker.status(), .needsUserApproval)
    }

    func testGrantedProbeAllowsActivity() {
        let checker = FullDiskAccessChecker(accessProbe: { true })

        XCTAssertEqual(checker.status(), .granted)
    }
}

private final class SequencedAccessProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Bool]

    init(_ results: [Bool]) {
        self.results = results
    }

    func next() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return results.isEmpty ? false : results.removeFirst()
    }
}
