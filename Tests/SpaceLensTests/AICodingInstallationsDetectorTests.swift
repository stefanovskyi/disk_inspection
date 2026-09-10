import Foundation
import XCTest
@testable import SpaceLens

final class AICodingInstallationsDetectorTests: XCTestCase {
    func testApplicationManifestAndBundledCLIProduceOneInstallation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let applications = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        let app = applications.appendingPathComponent("ChatGPT.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try writePlist([
            "CFBundleIdentifier": "com.openai.codex",
            "CFBundleShortVersionString": "26.901.51231",
            "CFBundleVersion": "8109"
        ], to: app.appendingPathComponent("Contents/Info.plist"))
        let bundledCLI = resources.appendingPathComponent("codex")
        try Data([0x00]).write(to: bundledCLI)
        let bin = fixture.root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("codex"),
            withDestinationURL: bundledCLI
        )

        let result = try await AICodingInstallationsDetector().detect(
            request: fixture.request(path: bin.path, applicationDirectories: [applications])
        )
        let installations = result[.codex] ?? []
        let installation = try XCTUnwrap(installations.first)

        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installation.surface, .nativeApplication)
        XCTAssertEqual(installation.version?.value, "26.901.51231")
        XCTAssertEqual(installation.build?.value, "8109")
        XCTAssertEqual(installation.version?.source.kind, .appManifest)
        XCTAssertEqual(installation.components.map(\.name), ["Bundled Codex CLI"])
        XCTAssertEqual(installation.entryPoints.map(\.name), ["codex"])
        XCTAssertTrue(installation.isOnProcessPath)
        XCTAssertNil(installation.installedOrUpdatedAt)
        XCTAssertEqual(installation.observedFileDate?.confidence, .heuristic)
    }

    func testAliasesAndRetainedReleasesAreGroupedUnderOneInstallation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let releases = fixture.home.appendingPathComponent(".local/share/cursor-agent/versions")
        let active = releases.appendingPathComponent("2026.02.13-41ac335", isDirectory: true)
        let previous = releases.appendingPathComponent("2026.01.28-1234567", isDirectory: true)
        let binary = active.appendingPathComponent("cursor-agent")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data([0x01]).write(to: binary)
        try Data([0x01]).write(to: previous.appendingPathComponent("cursor-agent"))
        let bin = fixture.home.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("agent"),
            withDestinationURL: binary
        )
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("cursor-agent"),
            withDestinationURL: binary
        )

        let result = try await AICodingInstallationsDetector().detect(
            request: fixture.request(path: bin.path)
        )
        let installations = (result[.cursor] ?? []).filter { $0.surface == .commandLine }
        let installation = try XCTUnwrap(installations.first)

        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installation.version?.value, "2026.02.13-41ac335")
        XCTAssertEqual(Set(installation.entryPoints.map(\.name)), ["agent", "cursor-agent"])
        XCTAssertEqual(installation.retainedReleases.count, 2)
        XCTAssertEqual(installation.retainedReleases.filter(\.isActive).count, 1)
        XCTAssertTrue(installation.isOnProcessPath)
    }

    func testSamePackageInTwoNVMVersionsRemainsTwoInstallations() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for (node, version) in [("v20.1.0", "1.2.3"), ("v22.2.0", "1.4.0")] {
            let package = fixture.home.appendingPathComponent(
                ".nvm/versions/node/\(node)/lib/node_modules/opencode-ai",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try writeJSON(["name": "opencode-ai", "version": version], to: package.appendingPathComponent("package.json"))
        }

        let result = try await AICodingInstallationsDetector().detect(request: fixture.request())
        let installations = (result[.openCode] ?? []).filter {
            $0.installMethod?.value == .npm
        }

        XCTAssertEqual(installations.count, 2)
        XCTAssertEqual(Set(installations.compactMap { $0.version?.value }), ["1.2.3", "1.4.0"])
        XCTAssertEqual(Set(installations.map(\.rootURL.path)).count, 2)
    }

    func testBunPnpmAndYarnLayoutsRetainTheirInstallMethods() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let packages: [(String, String)] = [
            (".bun/install/global/node_modules/opencode-ai", "1.1.0"),
            (".config/yarn/global/node_modules/opencode-ai", "1.2.0"),
            (".local/share/pnpm/global/5/node_modules/opencode-ai", "1.3.0")
        ]
        for (relativePath, version) in packages {
            let package = fixture.home.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try writeJSON(
                ["name": "opencode-ai", "version": version],
                to: package.appendingPathComponent("package.json")
            )
        }

        let result = try await AICodingInstallationsDetector().detect(request: fixture.request())
        let installs = result[.openCode] ?? []

        XCTAssertEqual(Set(installs.compactMap { $0.installMethod?.value }), [.bun, .pnpm, .yarn])
        XCTAssertEqual(Set(installs.compactMap { $0.version?.value }), ["1.1.0", "1.2.0", "1.3.0"])
    }

    func testLookalikeAndOversizedPackageManifestsAreIgnored() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let versions = fixture.home.appendingPathComponent(".nvm/versions/node")
        let lookalike = versions.appendingPathComponent(
            "v20/lib/node_modules/opencode-ai",
            isDirectory: true
        )
        let oversized = versions.appendingPathComponent(
            "v22/lib/node_modules/opencode-ai",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: lookalike, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oversized, withIntermediateDirectories: true)
        try writeJSON(
            ["name": "not-opencode", "version": "9.9.9"],
            to: lookalike.appendingPathComponent("package.json")
        )
        try Data(repeating: 0x20, count: 1_048_577)
            .write(to: oversized.appendingPathComponent("package.json"))

        let result = try await AICodingInstallationsDetector().detect(request: fixture.request())

        XCTAssertTrue((result[.openCode] ?? []).isEmpty)
    }

    func testHomebrewReceiptSuppliesAuthoritativeVersionAndEventDate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let prefix = fixture.root.appendingPathComponent("homebrew", isDirectory: true)
        let versionRoot = prefix.appendingPathComponent("Cellar/opencode/1.18.29", isDirectory: true)
        try FileManager.default.createDirectory(at: versionRoot, withIntermediateDirectories: true)
        try writeJSON(
            ["time": 1_788_976_800, "source": ["version": "1.18.29"]],
            to: versionRoot.appendingPathComponent("INSTALL_RECEIPT.json")
        )
        let opt = prefix.appendingPathComponent("opt", isDirectory: true)
        try FileManager.default.createDirectory(at: opt, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: opt.appendingPathComponent("opencode"),
            withDestinationURL: versionRoot
        )

        let result = try await AICodingInstallationsDetector().detect(
            request: fixture.request(homebrewPrefixes: [prefix])
        )
        let installation = try XCTUnwrap(
            result[.openCode]?.first { $0.installMethod?.value == .homebrewFormula }
        )

        XCTAssertEqual(installation.version?.value, "1.18.29")
        XCTAssertEqual(installation.version?.confidence, .authoritative)
        XCTAssertEqual(installation.installedOrUpdatedAt?.value.timeIntervalSince1970, 1_788_976_800)
        XCTAssertEqual(installation.installedOrUpdatedAt?.source.kind, .homebrewReceipt)
    }

    func testHomebrewCaskReceiptIsCorrelatedWithApplicationBundle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let applications = fixture.root.appendingPathComponent("Applications", isDirectory: true)
        let app = applications.appendingPathComponent("Cursor.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        try writePlist([
            "CFBundleIdentifier": "com.todesktop.230313mzl4w4u92",
            "CFBundleShortVersionString": "3.19.19"
        ], to: app.appendingPathComponent("Contents/Info.plist"))

        let prefix = fixture.root.appendingPathComponent("homebrew", isDirectory: true)
        let metadata = prefix.appendingPathComponent(
            "Caskroom/cursor/.metadata",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try writeJSON(
            ["time": 1_788_976_800, "source": ["version": "3.19.19"]],
            to: metadata.appendingPathComponent("INSTALL_RECEIPT.json")
        )

        let result = try await AICodingInstallationsDetector().detect(
            request: fixture.request(
                applicationDirectories: [applications],
                homebrewPrefixes: [prefix]
            )
        )
        let applicationsFound = (result[.cursor] ?? []).filter {
            $0.surface == .nativeApplication
        }
        let installation = try XCTUnwrap(applicationsFound.first)

        XCTAssertEqual(applicationsFound.count, 1)
        XCTAssertEqual(installation.rootURL.standardizedFileURL, app.standardizedFileURL)
        XCTAssertEqual(installation.version?.value, "3.19.19")
        XCTAssertEqual(installation.installMethod?.value, .homebrewCask)
        XCTAssertEqual(installation.installedOrUpdatedAt?.source.kind, .homebrewReceipt)
    }

    func testAnalyzerKeepsInstallationIndependentFromStorage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let installation = AICodingToolInstallation(
            toolID: .claudeCode,
            surface: .commandLine,
            displayName: "Claude Code",
            rootURL: fixture.root.appendingPathComponent("claude")
        )
        let detector = FixedInstallationsDetector(values: [.claudeCode: [installation]])
        let analyzer = AICodingToolsAnalyzer(
            installationsDetector: detector,
            rootDescriptors: []
        )

        let report = try await analyzer.analyze(request: fixture.request())
        let claude = try XCTUnwrap(report.tools.first { $0.id == .claudeCode })

        XCTAssertEqual(claude.installations, [installation])
        XCTAssertTrue(claude.hasRecognizedInstallation)
        XCTAssertFalse(claude.hasMeasuredStorage)
        XCTAssertEqual(report.totalSize, 0)
    }

    private func writePlist(_ value: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value).write(to: url)
    }
}

private struct FixedInstallationsDetector: AICodingInstallationsDetecting {
    let values: [AICodingToolID: [AICodingToolInstallation]]

    func detect(
        request: AICodingToolsRequest
    ) async throws -> [AICodingToolID: [AICodingToolInstallation]] {
        values
    }
}

private struct Fixture {
    let root: URL
    let home: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpaceLensInstallations-\(UUID().uuidString)",
            isDirectory: true
        )
        home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func request(
        path: String = "",
        applicationDirectories: [URL] = [],
        homebrewPrefixes: [URL] = []
    ) -> AICodingToolsRequest {
        AICodingToolsRequest(
            homeDirectory: home,
            applicationSupportDirectory: home.appendingPathComponent("Library/Application Support"),
            environment: path.isEmpty ? [:] : ["PATH": path],
            projectRoots: [],
            applicationDirectories: applicationDirectories,
            homebrewPrefixes: homebrewPrefixes
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
