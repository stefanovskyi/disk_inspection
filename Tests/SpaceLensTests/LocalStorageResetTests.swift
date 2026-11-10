import Foundation
import XCTest
@testable import SpaceLens

final class LocalStorageResetTests: XCTestCase {
    func testResetRemovesPreferencesAndSupportFoldersWithoutFollowingLinks() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SpaceLensReset-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let outside = root.appendingPathComponent("Scanned", isDirectory: true)
        let linkedSupport = root.appendingPathComponent("LinkedSupport", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("summary".utf8).write(to: support.appendingPathComponent("PreviousScans.json"))
        let keptFile = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keptFile)
        try fileManager.createSymbolicLink(at: linkedSupport, withDestinationURL: outside)

        let domain = "local.spacelens.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "layout.sidebarVisible")

        let failures = LocalStorageReset(
            defaults: defaults,
            defaultsDomain: domain,
            directories: [support, linkedSupport, root.appendingPathComponent("Missing")]
        ).perform()

        XCTAssertTrue(failures.isEmpty)
        XCTAssertNil(defaults.object(forKey: "layout.sidebarVisible"))
        XCTAssertFalse(fileManager.fileExists(atPath: support.path))
        XCTAssertNil(try? fileManager.attributesOfItem(atPath: linkedSupport.path))
        XCTAssertTrue(fileManager.fileExists(atPath: keptFile.path))
    }

    func testCurrentApplicationResetIncludesPreviousScanFolder() {
        let reset = LocalStorageReset.forCurrentApplication()
        XCTAssertTrue(reset.directories.contains(PreviousScanStore.defaultDirectoryURL))
    }
}
