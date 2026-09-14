import Foundation
import XCTest
@testable import SpaceLens

final class DeveloperStorageAnalyzerTests: XCTestCase {
    func testKeepsMarkerlessNodeModulesOutOfProjectsAndPrunesManagerHomes() async throws {
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
        XCTAssertTrue(node.locations.filter { $0.scope == .project }.isEmpty)
        XCTAssertEqual(node.unattributedLocations.map { $0.url.path }, [projectModules.path])
        XCTAssertTrue(node.sharedLocations.contains { $0.url == home.appendingPathComponent(".npm") })
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

    func testAttributesNestedNodeModulesToNearestMarkedProjectRoot() async throws {
        let root = temporaryDirectory(named: "NestedNodeModules")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = home.appendingPathComponent("project", isDirectory: true)
        let modules = project.appendingPathComponent("dist/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data(repeating: 0x41, count: 8_192).write(to: modules.appendingPathComponent("dependency.bin"))

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                automaticProjectContainers: [home],
                projectContainers: []
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        let location = try XCTUnwrap(node.locations.first { $0.url == modules.standardizedFileURL })
        XCTAssertEqual(location.projectURL, project.standardizedFileURL)
        XCTAssertEqual(location.evidence, .projectMarker)
    }

    func testClassifiesInstalledEditorDependenciesAsToolManagedEvenWithManifest() async throws {
        let root = temporaryDirectory(named: "ToolManaged")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let extensionRoot = home.appendingPathComponent(
            ".vscode/extensions/publisher.extension-1.0.0",
            isDirectory: true
        )
        let modules = extensionRoot.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{}".utf8).write(to: extensionRoot.appendingPathComponent("package.json"))
        try Data(repeating: 0x41, count: 8_192).write(to: modules.appendingPathComponent("dependency.bin"))

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                automaticProjectContainers: [home],
                projectContainers: []
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        let location = try XCTUnwrap(node.locations.first { $0.url == modules.standardizedFileURL })
        XCTAssertEqual(location.scope, .toolManaged)
        XCTAssertEqual(location.evidence, .toolManagedPath)
        XCTAssertEqual(location.kind, .installedTools)
        XCTAssertNil(location.projectURL)
        XCTAssertTrue(node.projects.isEmpty)
    }

    func testClassifiesAntigravityExtensionDependenciesAsToolManaged() async throws {
        let root = temporaryDirectory(named: "AntigravityExtensions")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let extensionRoots = [
            home.appendingPathComponent(
                ".antigravity/extensions/publisher.extension-1.0.0",
                isDirectory: true
            ),
            home.appendingPathComponent(
                ".antigravity-ide/extensions/publisher.extension-1.0.0/out/client",
                isDirectory: true
            )
        ]
        let moduleDirectories = extensionRoots.map {
            $0.appendingPathComponent("node_modules", isDirectory: true)
        }
        for (extensionRoot, modules) in zip(extensionRoots, moduleDirectories) {
            try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: extensionRoot.appendingPathComponent("package.json"))
            try Data(repeating: 0x41, count: 8_192)
                .write(to: modules.appendingPathComponent("dependency.bin"))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                automaticProjectContainers: [home],
                projectContainers: []
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        let matching = node.locations.filter { moduleDirectories.contains($0.url) }
        XCTAssertEqual(matching.count, moduleDirectories.count)
        XCTAssertTrue(matching.allSatisfy { $0.scope == .toolManaged })
        XCTAssertTrue(matching.allSatisfy { $0.evidence == .toolManagedPath })
        XCTAssertTrue(matching.allSatisfy { $0.projectURL == nil })
        XCTAssertTrue(node.projects.isEmpty)
    }

    func testOmitsEmptyMeasuredProjectArtifacts() async throws {
        let root = temporaryDirectory(named: "EmptyProjectArtifact")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = home.appendingPathComponent("project", isDirectory: true)
        let modules = project.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                automaticProjectContainers: [home],
                projectContainers: []
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        XCTAssertTrue(node.locations.isEmpty)
        XCTAssertTrue(node.projects.isEmpty)
    }

    func testTreatsExplicitlySelectedMarkerlessFolderAsProject() async throws {
        let root = temporaryDirectory(named: "SelectedProject")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = root.appendingPathComponent("selected-project", isDirectory: true)
        let modules = project.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 8_192).write(to: modules.appendingPathComponent("dependency.bin"))

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                projectContainers: [project]
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        let location = try XCTUnwrap(node.locations.first { $0.url == modules.standardizedFileURL })
        XCTAssertEqual(location.scope, .project)
        XCTAssertEqual(location.evidence, .selectedFolder)
        XCTAssertEqual(location.projectURL, project.standardizedFileURL)
    }

    func testClassifiesNPrefixGlobalPackagesAsSharedWithoutDuplicateDiscovery() async throws {
        let root = temporaryDirectory(named: "NPrefix")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let prefix = home.appendingPathComponent("n-prefix", isDirectory: true)
        let modules = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 8_192).write(to: modules.appendingPathComponent("package.bin"))

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: ["N_PREFIX": prefix.path],
                automaticProjectContainers: [home],
                projectContainers: []
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        let matching = node.locations.filter { $0.url == modules.standardizedFileURL }
        let location = try XCTUnwrap(matching.first)
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(location.scope, .shared)
        XCTAssertEqual(location.evidence, .knownSharedPath)
        XCTAssertEqual(location.kind, .installedTools)
    }

    func testDiscoversConventionalHomeNPrefixWithoutShellEnvironment() async throws {
        let root = temporaryDirectory(named: "ConventionalNPrefix")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let prefix = home.appendingPathComponent("n", isDirectory: true)
        let versions = prefix.appendingPathComponent("n/versions/node/22.0.0", isDirectory: true)
        let modules = prefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 8_192).write(to: modules.appendingPathComponent("package.bin"))

        let report = try await DeveloperStorageAnalyzer().analyze(
            request: DeveloperStorageRequest(
                homeDirectory: home,
                environment: [:],
                automaticProjectContainers: [home],
                projectContainers: []
            )
        )
        let node = try XCTUnwrap(report.ecosystems.first { $0.id == .nodeAndWeb })
        let globalPackages = try XCTUnwrap(node.locations.first { $0.url == modules.standardizedFileURL })
        XCTAssertEqual(globalPackages.scope, .shared)
        XCTAssertEqual(globalPackages.kind, .installedTools)
        XCTAssertTrue(node.projects.isEmpty)
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
