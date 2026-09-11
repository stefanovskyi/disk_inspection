import Foundation
import XCTest
@testable import SpaceLens

final class AICodingToolsAnalyzerTests: XCTestCase {
    func testBuiltInCatalogUsesAdditiveCustomHomesAndExpectedCategories() {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let customClaude = home.appendingPathComponent("custom-claude")
        let customCodex = home.appendingPathComponent("custom-codex")
        let request = AICodingToolsRequest(
            homeDirectory: home,
            applicationSupportDirectory: appSupport,
            environment: [
                "CLAUDE_CONFIG_DIR": customClaude.path,
                "CODEX_HOME": customCodex.path
            ],
            projectRoots: [home.appendingPathComponent("Project")]
        )
        let definitions = AICodingToolsCatalog.definitions(for: request)
        let roots = AICodingToolsCatalog.rootDescriptors(for: request)

        XCTAssertEqual(
            definitions.map(\.metadata.id),
            [.cursor, .claudeCode, .codex, .antigravity, .openCode]
        )
        XCTAssertTrue(definitions.allSatisfy { definition in
            definition.roots.allSatisfy { $0.toolID == definition.metadata.id }
        })

        XCTAssertTrue(roots.contains { $0.toolID == .claudeCode && $0.url == home.appendingPathComponent(".claude") })
        XCTAssertTrue(roots.contains {
            $0.toolID == .claudeCode && $0.url.standardizedFileURL.path == customClaude.path
        })
        XCTAssertTrue(roots.contains { $0.toolID == .codex && $0.url == home.appendingPathComponent(".codex") })
        XCTAssertTrue(roots.contains {
            $0.toolID == .codex && $0.url.standardizedFileURL.path == customCodex.path
        })
        XCTAssertTrue(roots.contains {
            $0.toolID == .antigravity
                && $0.url == home.appendingPathComponent(".gemini/antigravity-cli")
        })

        let cursor = try? XCTUnwrap(roots.first {
            $0.toolID == .cursor && $0.url == appSupport.appendingPathComponent("Cursor")
        })
        XCTAssertEqual(
            cursor?.category(for: appSupport.appendingPathComponent("Cursor/User/History/edit")),
            .recovery
        )
        XCTAssertEqual(
            cursor?.category(for: appSupport.appendingPathComponent("Cursor/User/workspaceStorage/db")),
            .other
        )

        let claude = try? XCTUnwrap(roots.first {
            $0.toolID == .claudeCode && $0.url == home.appendingPathComponent(".claude")
        })
        XCTAssertEqual(
            claude?.category(for: home.appendingPathComponent(".claude/plugins/cache/package")),
            .extensions
        )
        XCTAssertEqual(
            claude?.category(for: home.appendingPathComponent(".claude/projects/repo/memory/MEMORY.md")),
            .configuration
        )

        let antigravity = try? XCTUnwrap(roots.first {
            $0.toolID == .antigravity && $0.url == home.appendingPathComponent(".gemini/antigravity")
        })
        XCTAssertEqual(
            antigravity?.category(
                for: home.appendingPathComponent(
                    ".gemini/antigravity/brain/task/.system_generated/logs/transcript.jsonl"
                )
            ),
            .conversations
        )
    }

    func testOpenCodeCatalogResolvesKnownRootsAndComponentCategories() throws {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let project = home.appendingPathComponent("Project", isDirectory: true)
        let customData = URL(fileURLWithPath: "/Volumes/OpenCodeData", isDirectory: true)
        let customConfig = URL(fileURLWithPath: "/Volumes/OpenCodeConfig", isDirectory: true)
        let customCache = URL(fileURLWithPath: "/Volumes/OpenCodeCache", isDirectory: true)
        let customState = URL(fileURLWithPath: "/Volumes/OpenCodeState", isDirectory: true)
        let additionalConfig = URL(fileURLWithPath: "/Volumes/OpenCodeAdditional", isDirectory: true)
        let request = AICodingToolsRequest(
            homeDirectory: home,
            applicationSupportDirectory: appSupport,
            environment: [
                "XDG_DATA_HOME": customData.path,
                "XDG_CONFIG_HOME": customConfig.path,
                "XDG_CACHE_HOME": customCache.path,
                "XDG_STATE_HOME": customState.path,
                "OPENCODE_CONFIG_DIR": additionalConfig.path
            ],
            projectRoots: [project]
        )
        let definition = OpenCodeCatalog.definition(for: request)
        let roots = definition.roots
        func containsRoot(_ url: URL) -> Bool {
            roots.contains {
                $0.url.standardizedFileURL.path == url.standardizedFileURL.path
            }
        }

        XCTAssertEqual(definition.metadata.id, .openCode)
        XCTAssertEqual(Set(roots.map { $0.url.standardizedFileURL.path }).count, roots.count)
        XCTAssertTrue(containsRoot(home.appendingPathComponent(".local/share/opencode")))
        XCTAssertTrue(containsRoot(customData.appendingPathComponent("opencode")))
        XCTAssertTrue(containsRoot(home.appendingPathComponent(".config/opencode")))
        XCTAssertTrue(containsRoot(customConfig.appendingPathComponent("opencode")))
        XCTAssertTrue(containsRoot(home.appendingPathComponent(".cache/opencode")))
        XCTAssertTrue(containsRoot(customCache.appendingPathComponent("opencode")))
        XCTAssertTrue(containsRoot(home.appendingPathComponent(".local/state/opencode")))
        XCTAssertTrue(containsRoot(customState.appendingPathComponent("opencode")))
        XCTAssertTrue(containsRoot(additionalConfig))
        XCTAssertTrue(containsRoot(home.appendingPathComponent(".opencode")))
        XCTAssertTrue(containsRoot(appSupport.appendingPathComponent("ai.opencode.desktop")))
        XCTAssertTrue(containsRoot(appSupport.appendingPathComponent("ai.opencode.desktop.beta")))
        XCTAssertTrue(roots.contains {
            $0.url.path == "/Library/Application Support/opencode"
        })
        XCTAssertTrue(containsRoot(project.appendingPathComponent(".opencode")))

        let data = try XCTUnwrap(roots.first {
            $0.url.standardizedFileURL.path
                == home.appendingPathComponent(".local/share/opencode").standardizedFileURL.path
        })
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("opencode.db-wal")), .conversations)
        XCTAssertEqual(
            data.category(for: data.url.appendingPathComponent("opencode-canary.db-shm")),
            .conversations
        )
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("project/session")), .conversations)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("storage/session")), .conversations)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("snapshot/repo")), .recovery)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("plans/task.md")), .artifacts)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("worktree/repo")), .worktrees)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("repos/reference")), .worktrees)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("log/latest.log")), .logs)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("auth.json")), .configuration)
        XCTAssertEqual(data.category(for: data.url.appendingPathComponent("unknown.bin")), .other)

        let config = try XCTUnwrap(roots.first {
            $0.url.standardizedFileURL.path
                == home.appendingPathComponent(".config/opencode").standardizedFileURL.path
        })
        XCTAssertEqual(config.category(for: config.url.appendingPathComponent("agents/reviewer.md")), .configuration)
        XCTAssertEqual(config.category(for: config.url.appendingPathComponent("agent/legacy.md")), .configuration)
        XCTAssertEqual(config.category(for: config.url.appendingPathComponent("plugins/tool.ts")), .extensions)
        XCTAssertEqual(config.category(for: config.url.appendingPathComponent("node_modules/pkg")), .extensions)

        let cache = try XCTUnwrap(roots.first {
            $0.url.standardizedFileURL.path
                == home.appendingPathComponent(".cache/opencode").standardizedFileURL.path
        })
        XCTAssertEqual(cache.category(for: cache.url.appendingPathComponent("bin/ripgrep")), .extensions)
        XCTAssertEqual(cache.category(for: cache.url.appendingPathComponent("models.json")), .caches)

        let state = try XCTUnwrap(roots.first {
            $0.url.standardizedFileURL.path
                == home.appendingPathComponent(".local/state/opencode").standardizedFileURL.path
        })
        XCTAssertEqual(
            state.category(for: state.url.appendingPathComponent("prompt-history.jsonl")),
            .conversations
        )

        let desktop = try XCTUnwrap(roots.first {
            $0.url.standardizedFileURL.path
                == appSupport.appendingPathComponent("ai.opencode.desktop").standardizedFileURL.path
        })
        XCTAssertEqual(desktop.category(for: desktop.url.appendingPathComponent("Cache/data")), .caches)
        XCTAssertEqual(desktop.category(for: desktop.url.appendingPathComponent("logs/main.log")), .logs)
        XCTAssertEqual(desktop.category(for: desktop.url.appendingPathComponent("cli/opencode")), .extensions)
        XCTAssertEqual(
            desktop.category(for: desktop.url.appendingPathComponent("opencode.global.dat")),
            .configuration
        )

        let projectData = try XCTUnwrap(roots.first {
            $0.url.standardizedFileURL.path
                == project.appendingPathComponent(".opencode").standardizedFileURL.path
        })
        XCTAssertEqual(projectData.category(for: projectData.url.appendingPathComponent("plans/task.md")), .artifacts)
        XCTAssertEqual(projectData.category(for: projectData.url.appendingPathComponent("plugins/tool.ts")), .extensions)
        XCTAssertFalse(roots.contains { $0.url.path.contains("/.claude") })
        XCTAssertFalse(roots.contains { $0.url.standardizedFileURL == project.standardizedFileURL })
    }

    func testOpenCodeCatalogIgnoresRelativeXDGValuesAndDeduplicatesDefaults() {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let defaultDataBase = home.appendingPathComponent(".local/share")
        let defaultStateBase = home.appendingPathComponent(".local/state")
        let request = AICodingToolsRequest(
            homeDirectory: home,
            applicationSupportDirectory: appSupport,
            environment: [
                "XDG_DATA_HOME": defaultDataBase.path,
                "XDG_CONFIG_HOME": "relative-config",
                "XDG_CACHE_HOME": "",
                "XDG_STATE_HOME": defaultStateBase.path,
                "OPENCODE_CONFIG_DIR": "relative-additional-config"
            ],
            projectRoots: []
        )
        let roots = OpenCodeCatalog.definition(for: request).roots
        let paths = roots.map { $0.url.standardizedFileURL.path }

        XCTAssertEqual(paths.count { $0 == home.appendingPathComponent(".local/share/opencode").path }, 1)
        XCTAssertEqual(paths.count { $0 == home.appendingPathComponent(".local/state/opencode").path }, 1)
        XCTAssertFalse(paths.contains(home.appendingPathComponent("relative-config/opencode").path))
        XCTAssertFalse(paths.contains(home.appendingPathComponent("relative-additional-config").path))
    }

    func testAnalyzerClassifiesEveryObservedItemBeforeTreeCompaction() async throws {
        let root = temporaryDirectory(named: "Classification")
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let caches = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<(DiskScanner.retainedChildLimit + 20) {
            try Data(repeating: UInt8(index % 255), count: 1_024)
                .write(to: sessions.appendingPathComponent("session-\(index).jsonl"))
        }
        try Data(repeating: 0x41, count: 8_192)
            .write(to: caches.appendingPathComponent("index.bin"))

        let toolID = AICodingToolID(rawValue: "synthetic-agent")
        let descriptor = AICodingRootDescriptor(
            toolID: toolID,
            name: "Synthetic agent data",
            url: root,
            explanation: "Test fixture",
            defaultCategory: .other,
            rules: [
                .init("sessions", category: .conversations),
                .init("cache", category: .caches)
            ]
        )
        let analyzer = AICodingToolsAnalyzer(rootDescriptors: [descriptor])
        let report = try await analyzer.analyze(request: request(at: root))
        let baseline = try await DiskScanner().scan(url: root)
        let tool = try XCTUnwrap(report.tools.first { $0.id == toolID })

        XCTAssertEqual(tool.size, baseline.root.size)
        XCTAssertEqual(tool.itemCount, baseline.itemsScanned)
        XCTAssertEqual(tool.categories.reduce(0) { $0 + $1.size }, tool.size)
        XCTAssertNotNil(tool.latestModificationDate)
        XCTAssertNotNil(tool.categories.first { $0.category == .conversations })
        XCTAssertNotNil(tool.categories.first { $0.category == .caches })
        let location = try XCTUnwrap(tool.locations.first)
        let retainedRoot = try XCTUnwrap(location.root)
        XCTAssertEqual(retainedRoot.url.standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(retainedRoot.size, baseline.root.size)
        XCTAssertNotNil(retainedRoot.children.first { $0.name == "sessions" })
        XCTAssertNotNil(retainedRoot.children.first { $0.name == "cache" })
        XCTAssertGreaterThan(baseline.diagnostics.discardedNodes, 0)
    }

    func testOverlappingRootsAreScannedAndCountedOnce() async throws {
        let root = temporaryDirectory(named: "Overlap")
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 4_096)
            .write(to: root.appendingPathComponent("outside.bin"))
        try Data(repeating: 0x42, count: 8_192)
            .write(to: nested.appendingPathComponent("inside.bin"))

        let descriptors = [
            AICodingRootDescriptor(
                toolID: .cursor,
                name: "Parent",
                url: root,
                explanation: "Parent fixture",
                defaultCategory: .other,
                rules: []
            ),
            AICodingRootDescriptor(
                toolID: .cursor,
                name: "Nested",
                url: nested,
                explanation: "Nested fixture",
                defaultCategory: .worktrees,
                rules: []
            ),
            AICodingRootDescriptor(
                toolID: .codex,
                name: "Same physical root",
                url: root,
                explanation: "Exact overlap fixture",
                defaultCategory: .artifacts,
                rules: []
            )
        ]
        let report = try await AICodingToolsAnalyzer(rootDescriptors: descriptors)
            .analyze(request: request(at: root))
        let baseline = try await DiskScanner().scan(url: root)
        let tool = try XCTUnwrap(report.tools.first { $0.id == .cursor })

        XCTAssertEqual(tool.size, baseline.root.size)
        XCTAssertEqual(tool.itemCount, baseline.itemsScanned)
        XCTAssertEqual(tool.locations.count, 1)
        XCTAssertEqual(tool.locations.reduce(0) { $0 + $1.size }, baseline.root.size)
        XCTAssertTrue(tool.locations.allSatisfy { $0.status == .measured })
        let location = try XCTUnwrap(tool.locations.first)
        let retainedNested = try XCTUnwrap(location.root?.node(at: nested))
        XCTAssertEqual(location.annotation(for: retainedNested).category, .worktrees)
        XCTAssertEqual(location.annotation(for: retainedNested).title, "Nested")
        XCTAssertEqual(report.totalSize, baseline.root.size)
        XCTAssertEqual(report.itemCount, baseline.itemsScanned)
        XCTAssertEqual(report.tools.first { $0.id == .codex }?.size, baseline.root.size)
        XCTAssertEqual(report.tools.first { $0.id == .codex }?.locations.count, 1)
        XCTAssertEqual(Set(tool.locations.map(\.id)).count, tool.locations.count)
    }

    func testKnownNestedRootSurvivesBoundedCompaction() async throws {
        let root = temporaryDirectory(named: "PriorityRetention")
        let nested = root.appendingPathComponent("known-tool-root", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<(DiskScanner.retainedChildLimit + 12) {
            try Data(repeating: 0x41, count: 4_096)
                .write(to: root.appendingPathComponent("large-\(index).bin"))
        }
        try Data([0x42]).write(to: nested.appendingPathComponent("small.bin"))

        let descriptors = [
            AICodingRootDescriptor(
                toolID: .cursor,
                name: "Parent",
                url: root,
                explanation: "Parent fixture",
                defaultCategory: .other,
                rules: []
            ),
            AICodingRootDescriptor(
                toolID: .codex,
                name: "Known nested root",
                url: nested,
                explanation: "Nested fixture",
                defaultCategory: .configuration,
                rules: []
            )
        ]

        let report = try await AICodingToolsAnalyzer(rootDescriptors: descriptors)
            .analyze(request: request(at: root))
        let cursorRoot = try XCTUnwrap(
            report.tools.first { $0.id == .cursor }?.locations.first?.root
        )
        let codexRoot = try XCTUnwrap(
            report.tools.first { $0.id == .codex }?.locations.first?.root
        )

        XCTAssertNotNil(cursorRoot.node(at: nested))
        XCTAssertEqual(codexRoot.url.standardizedFileURL, nested.standardizedFileURL)
        XCTAssertEqual(codexRoot.children.first?.name, "small.bin")
        XCTAssertTrue(cursorRoot.children.contains { $0.isAggregate })
    }

    func testUnavailableAncestorDoesNotHideMeasuredDescendantFromOverallTotals() {
        let parentURL = URL(fileURLWithPath: "/tmp/unavailable-agent", isDirectory: true)
        let childURL = parentURL.appendingPathComponent("measured", isDirectory: true)
        let childRoot = FileNode(
            url: childURL,
            name: "measured",
            size: 42,
            isDirectory: true,
            isReadable: true,
            children: [],
            itemCount: 1
        )
        let parent = AICodingStorageLocation(
            toolID: .cursor,
            name: "Unavailable parent",
            url: parentURL,
            explanation: "Fixture",
            status: .unreadable,
            root: nil,
            categories: [],
            defaultCategory: .other,
            rules: []
        )
        let child = AICodingStorageLocation(
            toolID: .codex,
            name: "Measured child",
            url: childURL,
            explanation: "Fixture",
            status: .measured,
            root: childRoot,
            categories: [],
            defaultCategory: .other,
            rules: []
        )
        let report = AICodingToolsReport(
            tools: [
                AICodingToolReport(
                    tool: AICodingToolsCatalog.metadata(for: .cursor),
                    locations: [parent]
                ),
                AICodingToolReport(
                    tool: AICodingToolsCatalog.metadata(for: .codex),
                    locations: [child]
                )
            ],
            startedAt: Date(),
            duration: 0
        )

        XCTAssertEqual(report.totalSize, 42)
        XCTAssertEqual(report.itemCount, 1)
        XCTAssertEqual(report.issueCount, 1)
    }

    func testAnalyzerSkipsLinkedRootWithoutFollowingIt() async throws {
        let parent = temporaryDirectory(named: "Linked")
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let link = parent.appendingPathComponent("tool-data")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try Data(repeating: 0x41, count: 4_096)
            .write(to: target.appendingPathComponent("private.jsonl"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let descriptor = AICodingRootDescriptor(
            toolID: .claudeCode,
            name: "Linked Claude data",
            url: link,
            explanation: "Test fixture",
            defaultCategory: .conversations,
            rules: []
        )
        let report = try await AICodingToolsAnalyzer(rootDescriptors: [descriptor])
            .analyze(request: request(at: parent))
        let location = try XCTUnwrap(
            report.tools.first { $0.id == .claudeCode }?.locations.first
        )

        XCTAssertEqual(location.status, .linked)
        XCTAssertEqual(location.size, 0)
        XCTAssertEqual(report.totalSize, 0)
    }

    func testMoreSpecificPathRuleOverridesParentCategory() {
        let root = URL(fileURLWithPath: "/tmp/agent", isDirectory: true)
        let descriptor = AICodingRootDescriptor(
            toolID: .antigravity,
            name: "Agent",
            url: root,
            explanation: "Test fixture",
            defaultCategory: .other,
            rules: [
                .init("brain", category: .artifacts),
                .init("brain/*/.system_generated/logs", category: .conversations)
            ]
        )

        XCTAssertEqual(
            descriptor.category(for: root.appendingPathComponent("brain/task/artifact.png")),
            .artifacts
        )
        XCTAssertEqual(
            descriptor.category(
                for: root.appendingPathComponent("brain/task/.system_generated/logs/session.json")
            ),
            .conversations
        )

        let nestedNode = FileNode(
            url: root.appendingPathComponent("brain/task/.system_generated/logs"),
            name: "logs",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: []
        )
        let location = AICodingStorageLocation(
            toolID: descriptor.toolID,
            name: descriptor.name,
            url: descriptor.url,
            explanation: descriptor.explanation,
            status: .measured,
            root: nil,
            categories: [],
            defaultCategory: descriptor.defaultCategory,
            rules: [
                .init(
                    "brain",
                    category: .artifacts,
                    title: "Task artifacts",
                    explanation: "Generated task files."
                ),
                .init(
                    "brain/*/.system_generated/logs",
                    category: .conversations,
                    title: "Conversation transcript",
                    explanation: "Conversation records produced for this task."
                )
            ]
        )
        let annotation = location.annotation(for: nestedNode)
        XCTAssertEqual(annotation.category, .conversations)
        XCTAssertEqual(annotation.title, "Conversation transcript")
        XCTAssertEqual(annotation.explanation, "Conversation records produced for this task.")
        XCTAssertTrue(annotation.isComponentRoot)
    }

    func testOnlyComponentRootsExposeVisibleCategoryContext() {
        let root = URL(fileURLWithPath: "/tmp/claude", isDirectory: true)
        let projectsURL = root.appendingPathComponent("projects", isDirectory: true)
        let projectURL = projectsURL.appendingPathComponent("-Users-fixture-Project", isDirectory: true)
        let location = AICodingStorageLocation(
            toolID: .claudeCode,
            name: "Claude Code data",
            url: root,
            explanation: "Claude Code data.",
            status: .measured,
            root: nil,
            categories: [],
            defaultCategory: .other,
            rules: [
                .init(
                    "projects",
                    category: .conversations,
                    title: "Claude projects",
                    explanation: "Project-specific Claude Code sessions and metadata."
                ),
                .init("projects/*/memory", category: .configuration)
            ],
            nodeDisplayNames: [projectURL.path: "Project (-Users-fixture-Project)"]
        )

        let projects = FileNode(
            url: projectsURL,
            name: "projects",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: []
        )
        let project = FileNode(
            url: projectURL,
            name: "-Users-fixture-Project",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: []
        )
        let memory = FileNode(
            url: projectURL.appendingPathComponent("memory", isDirectory: true),
            name: "memory",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: []
        )

        let projectsAnnotation = location.annotation(for: projects)
        XCTAssertEqual(projectsAnnotation.visibleCategory, .conversations)
        XCTAssertEqual(
            projectsAnnotation.visibleExplanation,
            "Project-specific Claude Code sessions and metadata."
        )

        let projectAnnotation = location.annotation(for: project)
        XCTAssertEqual(projectAnnotation.displayName, "Project (-Users-fixture-Project)")
        XCTAssertNil(projectAnnotation.visibleCategory)
        XCTAssertNil(projectAnnotation.visibleExplanation)

        let memoryAnnotation = location.annotation(for: memory)
        XCTAssertEqual(memoryAnnotation.visibleCategory, .configuration)
        XCTAssertNotNil(memoryAnnotation.visibleExplanation)
    }

    func testCancellationStopsAnalyzerWorker() async throws {
        let root = temporaryDirectory(named: "Cancellation")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        let gate = AnalyzerCancellationGate()
        let scanner = DiskScanner(directoryReader: { url, keys in
            gate.markStartedAndWait()
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: []
            )
        })
        let descriptor = AICodingRootDescriptor(
            toolID: .codex,
            name: "Codex fixture",
            url: root,
            explanation: "Test fixture",
            defaultCategory: .other,
            rules: []
        )
        let analyzer = AICodingToolsAnalyzer(scanner: scanner, rootDescriptors: [descriptor])
        let task = Task { try await analyzer.analyze(request: request(at: root)) }

        while !gate.hasStarted {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        task.cancel()
        gate.release()

        do {
            _ = try await task.value
            XCTFail("Cancelled analysis unexpectedly completed")
        } catch is CancellationError {
            // Expected.
        } catch ScanFailure.cancelled {
            // Equivalent cancellation surfaced by DiskScanner.
        }
    }

    func testAnalyzerReportsStalledLocationAndReturnsPartialReport() async throws {
        let root = temporaryDirectory(named: "Stalled")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = AnalyzerCancellationGate()
        let scanner = DiskScanner(
            stalledSubtreeTimeout: 0.05,
            shouldIsolateSubtree: { $0.standardizedFileURL == root.standardizedFileURL },
            directoryReader: { url, keys in
                gate.markStartedAndWait()
                return try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            }
        )
        let descriptor = AICodingRootDescriptor(
            toolID: .antigravity,
            name: "Stalled fixture",
            url: root,
            explanation: "Test fixture",
            defaultCategory: .other,
            rules: []
        )
        let report = try await AICodingToolsAnalyzer(
            scanner: scanner,
            rootDescriptors: [descriptor]
        ).analyze(request: request(at: root))
        gate.release()

        let location = try XCTUnwrap(
            report.tools.first { $0.id == .antigravity }?.locations.first
        )
        XCTAssertEqual(location.status, .stalled)
        XCTAssertEqual(report.issueCount, 1)
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpaceLensAI\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func request(at root: URL) -> AICodingToolsRequest {
        AICodingToolsRequest(
            homeDirectory: root,
            applicationSupportDirectory: root,
            environment: [:],
            projectRoots: []
        )
    }
}

private final class AnalyzerCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation = DispatchSemaphore(value: 0)
    private var started = false

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func markStartedAndWait() {
        lock.lock()
        started = true
        lock.unlock()
        continuation.wait()
    }

    func release() {
        continuation.signal()
    }
}
