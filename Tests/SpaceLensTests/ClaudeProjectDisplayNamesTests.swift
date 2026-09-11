import Foundation
import XCTest
@testable import SpaceLens

final class ClaudeProjectDisplayNamesTests: XCTestCase {
    func testRegisteredProjectUsesRealBasenameAndRetainsEncodedDirectoryName() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensClaudeNames-\(UUID().uuidString)", isDirectory: true)
        let claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
        let projectsDirectory = claudeDirectory.appendingPathComponent("projects", isDirectory: true)
        let projectPath = home.appendingPathComponent("Documents/projects/event-omnitool").path
        let encodedName = ClaudeProjectDisplayNames.encodedDirectoryName(for: projectPath)
        let encodedDirectory = projectsDirectory.appendingPathComponent(encodedName, isDirectory: true)
        try FileManager.default.createDirectory(at: encodedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let registry = try JSONSerialization.data(withJSONObject: [
            "projects": [projectPath: [String: String]()]
        ])
        try registry.write(to: home.appendingPathComponent(".claude.json"))

        let displayNames = ClaudeProjectDisplayNames.load(
            homeDirectory: home,
            claudeDirectory: claudeDirectory
        )

        XCTAssertEqual(
            displayNames[encodedDirectory.standardizedFileURL.path],
            "event-omnitool (\(encodedName))"
        )
    }

    func testFallbackRemovesConventionalHomeAndProjectsPrefix() {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let projectsDirectory = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let encodedName = "-Users-fixture-Documents-projects-vacation-calendar"

        let displayNames = ClaudeProjectDisplayNames.overrides(
            projectDirectory: projectsDirectory,
            directoryNames: [encodedName],
            registeredProjectPaths: [],
            homeDirectory: home
        )

        XCTAssertEqual(
            displayNames[projectsDirectory.appendingPathComponent(encodedName).standardizedFileURL.path],
            "vacation-calendar (\(encodedName))"
        )
    }
}
