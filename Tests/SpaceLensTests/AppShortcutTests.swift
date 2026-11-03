import XCTest
@testable import SpaceLens

final class AppShortcutTests: XCTestCase {
    func testMainDriveFindsStartupDiskAndOthersFollowSidebarOrder() {
        let startup = volume("/", name: "Macintosh HD")
        let second = volume("/Volumes/Projects", name: "Projects")
        let third = volume("/Volumes/Backup", name: "Backup")
        let fourth = volume("/Volumes/Archive", name: "Archive")
        let volumes = [second, startup, third, fourth]

        XCTAssertEqual(AppShortcut.mainDrive.volume(in: volumes), startup)
        XCTAssertEqual(AppShortcut.secondDrive.volume(in: volumes), second)
        XCTAssertEqual(AppShortcut.thirdDrive.volume(in: volumes), third)
    }

    func testUnavailableDrivesHaveNoDestination() {
        let startup = volume("/", name: "Macintosh HD")
        let external = volume("/Volumes/External", name: "External")

        for shortcut in AppShortcut.driveShortcuts {
            XCTAssertNil(shortcut.volume(in: []))
        }
        XCTAssertNil(AppShortcut.secondDrive.volume(in: [startup]))
        XCTAssertNil(AppShortcut.thirdDrive.volume(in: [startup, external]))
        XCTAssertNil(AppShortcut.mainDrive.volume(in: [external]), "An external disk must never take the main drive slot")
    }

    func testDriveDestinationsRefreshAfterUnmounting() {
        let startup = volume("/", name: "Macintosh HD")
        let external = volume("/Volumes/External", name: "External")
        let backup = volume("/Volumes/Backup", name: "Backup")

        XCTAssertEqual(AppShortcut.thirdDrive.volume(in: [startup, external, backup]), backup)
        XCTAssertEqual(AppShortcut.secondDrive.volume(in: [startup, backup]), backup)
        XCTAssertNil(AppShortcut.thirdDrive.volume(in: [startup, backup]))
    }

    private func volume(_ path: String, name: String) -> VolumeInfo {
        VolumeInfo(
            url: URL(fileURLWithPath: path), name: name,
            totalCapacity: 100, availableCapacity: 50,
            isExternal: path != "/", isReadOnly: false
        )
    }
}
