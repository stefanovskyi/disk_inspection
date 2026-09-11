import Foundation
import XCTest
@testable import SpaceLens

final class DeveloperStorageAnalyzerTests: XCTestCase {
    func testAutomaticallyDiscoversNodeModulesWithoutManifestAndPrunesManagerHomes() async throws {
        let root = temporaryDirectory(named: "AutomaticDiscovery")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let projectModules = home.appendingPathComponent("work/example/node_modules", isDirectory: true)
        let managerModules = home.appendingPathComponent(".npm/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: projectModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managerModules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 8_192)
            .write(to: projectModules.appendingPathComponent("dependency.bin"))
        try Data(repeating: 0x42, count: 8_192)
            .write(to: managerModules.appendingPathComponent("manager-internal.bin"))

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                automaticProjectContainers: [home],
                projectContainers: []
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        XCTAssertEqual(
            node.locations.filter { $0.scope == .project }.map { $0.url.path },
            [projectModules.path]
        )
        XCTAssertGreaterThan(node.projectSize, 0)
    }

    func testCurrentUserRequestSearchesHomeAutomatically() {
        let request = DeveloperStorageRequest.currentUser()
        XCTAssertEqual(
            request.automaticProjectContainers,
            [FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL]
        )
    }

    func testDiscoversOnlyValidatedProjectArtifacts() async throws {
        let root = temporaryDirectory(named: "Discovery")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let modules = project.appendingPathComponent("node_modules", isDirectory: true)
        let nextOutput = project.appendingPathComponent(".next", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nextOutput, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data(repeating: 0x41, count: 8_192).write(to: modules.appendingPathComponent("dependency.bin"))
        try Data(repeating: 0x43, count: 4_096).write(to: nextOutput.appendingPathComponent("output.bin"))
        try Data(repeating: 0x42, count: 8_192).write(to: project.appendingPathComponent("source.bin"))

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                projectContainers: [project]
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        XCTAssertEqual(node.locations.count, 2)
        XCTAssertTrue(node.locations.contains { $0.kind == .projectDependencies })
        XCTAssertTrue(node.locations.contains { $0.kind == .buildOutputs })
        XCTAssertGreaterThan(node.projectSize, 0)
        let projectReport = try XCTUnwrap(node.projects.first)
        XCTAssertEqual(node.projects.count, 1)
        XCTAssertEqual(projectReport.name, "project")
        XCTAssertEqual(projectReport.url, project.standardizedFileURL)
        XCTAssertEqual(projectReport.artifactCount, 2)
        XCTAssertEqual(projectReport.itemCount, node.locations.reduce(0) { $0 + $1.itemCount })
        XCTAssertEqual(projectReport.uniqueSize, node.projectSize)
        XCTAssertEqual(projectReport.issueCount, 0)
    }

    func testDeduplicatesHardLinksAndFavorsSharedStore() async throws {
        let root = temporaryDirectory(named: "HardLinks")
        let shared = root.appendingPathComponent("shared", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = shared.appendingPathComponent("package.bin")
        try Data(repeating: 0x41, count: 16_384).write(to: original)
        try FileManager.default.linkItem(at: original, to: project.appendingPathComponent("package.bin"))

        let descriptors = [
            DeveloperArtifactDescriptor(
                ecosystemID: .nodeAndWeb,
                scope: .shared,
                kind: .sharedCaches,
                name: "Store",
                url: shared
            ),
            DeveloperArtifactDescriptor(
                ecosystemID: .nodeAndWeb,
                scope: .project,
                kind: .projectDependencies,
                name: "Dependencies",
                url: project,
                projectURL: project
            )
        ]
        let report = try await DeveloperStorageAnalyzer(descriptors: descriptors).analyze(
            request: DeveloperStorageRequest(homeDirectory: root, environment: [:], projectContainers: [])
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        XCTAssertGreaterThan(report.referencedSize, report.totalSize)
        XCTAssertGreaterThan(node.sharedSize, 0)
        XCTAssertEqual(node.projectSize, 0)
    }

    func testLinkedVirtualEnvironmentIsReportedAndNotFollowed() async throws {
        let root = temporaryDirectory(named: "LinkedEnvironment")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let physical = root.appendingPathComponent("physical-environment", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: physical.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("[project]".utf8).write(to: project.appendingPathComponent("pyproject.toml"))
        try Data("home = /usr/bin".utf8).write(to: physical.appendingPathComponent("pyvenv.cfg"))
        try Data("python".utf8).write(to: physical.appendingPathComponent("bin/python"))
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent(".venv"),
            withDestinationURL: physical
        )

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(homeDirectory: home, environment: [:], projectContainers: [project])
        )
        let python = try XCTUnwrap(report.ecosystems.first { $0.id == .python })
        XCTAssertEqual(python.locations.count, 1)
        XCTAssertEqual(python.locations.first?.status, .linked)
        XCTAssertEqual(python.locations.first?.uniqueSize, 0)
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensDeveloper\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
