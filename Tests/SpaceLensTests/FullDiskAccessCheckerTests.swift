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

    func testScanEverythingNeedsApprovalBeforeIncludingStartupDisk() {
        let checker = FullDiskAccessChecker(accessProbe: { false })

        XCTAssertEqual(
            checker.status(for: ScanEverythingPlan(volumes: [startupVolume()])),
            .needsUserApproval
        )
    }

    func testScanEverythingNeedsApprovalEvenWithoutStartupDisk() {
        let checker = FullDiskAccessChecker(accessProbe: { false })

        XCTAssertEqual(
            checker.status(for: ScanEverythingPlan(volumes: [externalVolume()])),
            .needsUserApproval
        )
    }

    func testScanEverythingContinuesWhenFullDiskAccessIsGranted() {
        let checker = FullDiskAccessChecker(accessProbe: { true })

        XCTAssertEqual(
            checker.status(for: ScanEverythingPlan(volumes: [startupVolume()])),
            .granted
        )
    }

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

    private func startupVolume() -> VolumeInfo {
        VolumeInfo(
            url: URL(fileURLWithPath: "/", isDirectory: true),
            name: "Macintosh HD",
            totalCapacity: 100,
            availableCapacity: 50,
            isExternal: false,
            isReadOnly: false,
            uuid: "startup",
            isLocal: true
        )
    }

    private func externalVolume() -> VolumeInfo {
        VolumeInfo(
            url: URL(fileURLWithPath: "/Volumes/External", isDirectory: true),
            name: "External",
            totalCapacity: 100,
            availableCapacity: 50,
            isExternal: true,
            isReadOnly: false,
            uuid: "external",
            isLocal: true
        )
    }
}
