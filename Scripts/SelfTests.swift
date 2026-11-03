import Foundation

enum SelfTestFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

private struct StopDirectoryStreaming: Error {}

private func brandLogosExistForEveryCatalogEntry() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let directory = projectRoot.appendingPathComponent("Sources/SpaceLens/Resources/BrandLogos")
    let bundled = Set(
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".png") }
            .map { String($0.dropLast(4)) }
    )
    let cataloged = Set(BrandLogo.all.map(\.assetName))
    guard bundled == cataloged else {
        throw SelfTestFailure.failed(
            "Logo mismatch; missing PNG: \(cataloged.subtracting(bundled).sorted()), "
                + "not cataloged: \(bundled.subtracting(cataloged).sorted())"
        )
    }
    guard BrandLogo.all.count == cataloged.count else {
        throw SelfTestFailure.failed("BrandLogo.all lists a logo more than once")
    }
}

private func storageDescriptionsMatchOnlyKnownLocations() throws {
    func safety(_ path: String, directory: Bool = true) -> StorageItemDescription.Safety? {
        StorageItemDescription.resolve(url: URL(fileURLWithPath: path), isDirectory: directory)?.safety
    }
    let expectations: [(String, Bool, StorageItemDescription.Safety?)] = [
        ("/", true, .keep),
        ("/Applications", true, .reviewFirst),
        ("/Users/me", true, .keep),
        ("/Users/Shared", true, .reviewFirst),
        ("/Users/me/.ssh", true, .keep),
        ("/Users/me/.npm", true, .safeToClear),
        ("/Users/me/Library/Caches", true, .safeToClear),
        ("/Users/me/Library/Caches/com.example.app", true, .safeToClear),
        ("/Users/me/Library/Containers/com.example.app", true, .reviewFirst),
        ("/Users/me/Library/Keychains", true, .keep),
        ("/Users/me/Library/Developer/Xcode/DerivedData", true, .safeToClear),
        ("/private/var/folders", true, .keep),
        ("/private/var/folders/ab/cd/T", true, .keep),
        ("/var/folders", true, .keep),
        ("/System/Volumes/Data/Users/me/Library/Caches", true, .safeToClear),
        ("/Applications/Cursor.app", true, .reviewFirst),
        ("/System/Applications/Mail.app", true, .keep),
        ("/System/Library/Fonts/Thonburi.ttc", false, .keep),
        ("/usr/local/lib/custom", true, .reviewFirst),
        ("/Volumes/Backup", true, .reviewFirst),
        ("/work/app/node_modules", true, .safeToClear),
        ("/work/app/.git", true, .keep),
        ("/Users/me/Pictures/Photos Library.photoslibrary", true, .reviewFirst),
        ("/Users/me/Downloads/Installer.dmg", false, .reviewFirst),
        // Same names outside their known location stay undescribed.
        ("/work/Library", true, nil),
        ("/work/Library/Caches", true, nil),
        ("/work/Caches/thing", true, nil),
        ("/Users/me/projects/Library/Caches", true, nil),
        ("/Users/me/projects/Documents", true, nil),
        ("/Users/me/projects/app", true, nil),
        ("/work/node_modules", false, nil),
        ("/work/Foo.app", false, nil),
        ("/Users/Shared/Library", true, nil),
    ]
    for (path, directory, expected) in expectations {
        let actual = safety(path, directory: directory)
        guard actual == expected else {
            throw SelfTestFailure.failed("Description of \(path): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
    }

    for description in StorageItemDescriptionCatalog.all {
        guard description.text.count >= 20, description.text.count <= 200, description.text.hasSuffix(".") else {
            throw SelfTestFailure.failed("Description is not short, complete text: \(description.text)")
        }
    }
}

private func brandLogosIdentifyProductsAndStorageItems() throws {
    func expect<Value: Equatable>(_ actual: Value, _ expected: Value, _ label: String) throws {
        guard actual == expected else {
            throw SelfTestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    let tools = Dictionary(uniqueKeysWithValues: AICodingToolsCatalog.supportedTools.map { ($0.id, $0.logo) })
    try expect(tools[.cursor] ?? nil, .cursor, "Cursor tool")
    try expect(tools[.claudeCode] ?? nil, .claudeCode, "Claude Code tool")
    try expect(tools[.codex] ?? nil, .codex, "Codex tool")
    try expect(tools[.antigravity] ?? nil, .antigravity, "Antigravity tool")
    try expect(tools[.openCode] ?? nil, .openCode, "OpenCode tool")
    try expect(tools[.t3Code] ?? nil, .t3Code, "T3 Code tool")
    try expect(DeveloperEcosystemID.python.logo, .python, "Python ecosystem")

    let locations: [(String, BrandLogo?)] = [
        ("npm cache", .npm), ("Unattributed node_modules", .nodeJS), ("Next.js output", .nextJS),
        ("fnm Node versions", .nodeJS), ("uv Python versions", .uv), ("miniconda3 packages", .anaconda),
        ("Pyenv versions", .python), (".mypy_cache", .python), ("Gradle JDKs", .gradle),
        ("Homebrew openjdk@21", .java), ("Maven target", .maven), ("SDKMAN JDKs", .java),
        ("VS Code extension dependencies", .vsCode), ("Claude plugin dependencies", .claudeCode),
        ("Bundled assets", nil), ("Fluvial data", nil)
    ]
    for (name, logo) in locations {
        try expect(BrandLogoCatalog.logo(forStorageLocationNamed: name), logo, "Location \(name)")
    }

    let models: [(String, BrandLogo?)] = [
        ("qwen2.5:7b", .qwen), ("mlx-community/Llama-3.3", .meta), ("google/gemma-3", .gemma),
        ("phi4:latest", .microsoft), ("sapphire-7b", nil), ("my-finetune", nil)
    ]
    for (name, logo) in models {
        try expect(BrandLogoCatalog.logo(forModelNamed: name), logo, "Model \(name)")
    }

    func icon(_ path: String, directory: Bool = true) -> StorageItemIcon {
        StorageItemIcon.resolve(url: URL(fileURLWithPath: path), isDirectory: directory)
    }
    let support = "/Users/me/Library/Application Support"
    let cursor = URL(fileURLWithPath: "/Applications/Cursor.app")
    try expect(icon(cursor.path), .system(.file(cursor), fallback: .cursor), "App bundle")
    try expect(icon("/Users/me/.claude"), .brand(.claudeCode), "Claude home")
    try expect(icon("/Users/me/.aws"), .brand(.aws), "Dot folder")
    try expect(icon("/Users/me/.cache/uv"), .brand(.uv), "Tool cache folder")
    try expect(icon("/Users/me/.config/gcloud"), .brand(.googleCloud), "Tool config folder")
    try expect(icon("/work/app/node_modules"), .brand(.nodeJS), "node_modules")
    try expect(icon("/work/app/node_modules/react"), .brand(.react), "npm package")
    try expect(icon("/work/app/node_modules/@supabase/auth-js"), .brand(.supabase), "Scoped npm package")
    try expect(icon("/work/venv/lib/site-packages/torch"), .brand(.pyTorch), "Python package")
    try expect(icon("/opt/homebrew/Cellar/python@3.14"), .brand(.python), "Versioned formula")
    try expect(icon("/opt/homebrew/Cellar/kubernetes-cli"), .brand(.kubernetes), "Homebrew formula")
    try expect(icon("/work/main.py", directory: false), .brand(.python), "Python file")
    try expect(icon("/work/Package.swift", directory: false), .brand(.swift), "Swift manifest")
    try expect(icon("/work/schema.sql.tf", directory: false), .brand(.terraform), "Terraform file")
    try expect(icon("/Users/me/.zshrc", directory: false), .brand(.zsh), "Shell config")
    try expect(icon("/work/notes.pdf", directory: false), .system(.fileType("pdf"), fallback: nil), "Document type")
    try expect(icon("/work/Lib.framework"), .system(.fileType("framework"), fallback: nil), "Package folder")
    try expect(icon("/work/release.v2"), .generic, "Dotted folder is not a package")
    try expect(icon("/work/go", directory: false), .generic, "Extensionless file")
    try expect(icon("/work/Cursor"), .generic, "Same-named project folder")
    try expect(icon("/work/react"), .generic, "Same-named project outside packages")
    try expect(icon("/work/node_modules/signal"), .generic, "npm package named like an application")
    try expect(icon("/work/node_modules/box"), .generic, "npm package named like a service")
    try expect(icon("/work/node_modules/@supabase"), .brand(.supabase), "npm scope")
    try expect(icon("/work/share/react"), .generic, "Ordinary share folder")
    try expect(icon("/Users/me/.local/share/uv"), .brand(.uv), "XDG data folder")
    try expect(icon("/work/go"), .generic, "Go folder outside home")
    try expect(icon("/Users/me/go"), .brand(.go), "Go workspace in home")
    try expect(icon("/Users/me/Documents"), .system(.file(URL(fileURLWithPath: "/Users/me/Documents")), fallback: nil), "Home system folder")
    try expect(icon("/work/Documents"), .generic, "Same-named ordinary folder")
    try expect(icon("/Users/me/Library/Mail"), .system(.applicationNamed("Mail"), fallback: nil), "Library app folder")
    try expect(icon("\(support)/Cursor"), .system(.applicationNamed("Cursor"), fallback: .cursor), "Application Support folder")
    try expect(icon("\(support)/Claude"), .system(.applicationNamed("Claude"), fallback: .claude), "Claude desktop data")
    try expect(icon("\(support)/Code"), .system(.applicationNamed("Visual Studio Code"), fallback: .vsCode), "Application alias")
    try expect(icon("\(support)/Docker Desktop"), .system(.applicationNamed("Docker"), fallback: .docker), "Docker alias")
    try expect(icon("/Applications/DaVinci Resolve"), .system(.applicationNamed("DaVinci Resolve/DaVinci Resolve"), fallback: .daVinciResolve), "Application folder")
    try expect(icon("/Applications/Python 3.12"), .system(.applicationNamed("Python 3.12/Python 3.12"), fallback: .python), "Versioned application folder")
    try expect(
        icon("/Users/me/Library/Containers/com.tinyspeck.slackmacgap"),
        .system(.bundleIdentifier("com.tinyspeck.slackmacgap"), fallback: .slack),
        "Container folder"
    )
    try expect(
        icon("/Users/me/Library/Caches/com.hnc.Discord.ShipIt"),
        .system(.bundleIdentifier("com.hnc.Discord.ShipIt"), fallback: .discord),
        "Updater cache"
    )
    try expect(
        icon("/Users/me/Library/Group Containers/UBF8T346G9.com.microsoft.teams"),
        .system(.bundleIdentifier("com.microsoft.teams"), fallback: .microsoft),
        "Team-prefixed group container"
    )
    try expect(
        icon("/Users/me/Library/Group Containers/group.W5364U7YZB.io.tailscale.shared"),
        .system(.bundleIdentifier("io.tailscale.shared"), fallback: .tailscale),
        "App group container"
    )
    try expect(icon("/Users/me/Library/Group Containers/UBF8T346G9.Office"), .brand(.microsoft), "Team-only group container")
    try expect(
        icon("/Users/me/Library/Preferences/com.adobe.Photoshop.plist", directory: false),
        .system(.bundleIdentifier("com.adobe.Photoshop"), fallback: .adobe),
        "Preferences file"
    )
    try expect(icon("/work/com.example.notes"), .generic, "Dotted folder outside Library")
    try expect(icon("/Users/me/Library/Logs/warp.log", directory: false), .system(.fileType("log"), fallback: nil), "Log file is not a bundle")

    try expect(
        SystemIconSource.bundleIdentifierCandidates(for: "com.hnc.Discord.ShipIt"),
        ["com.hnc.Discord.ShipIt", "com.hnc.Discord", "com.hnc"],
        "Bundle identifier candidates"
    )
    for (name, logo) in [("Sublime Text 3", BrandLogo.sublimeText), ("python@3.14", .python), (".AWS", .aws), ("Adobe Camera Raw 15.0 Prefs", .adobe)] {
        try expect(BrandLogoCatalog.logo(forProductNamed: name), logo, "Product \(name)")
    }
    try expect(BrandLogoCatalog.logo(forProductNamed: "libpng"), nil, "Unbranded library")
}

@main
struct SpaceLensSelfTests {
    static func main() async throws {
        try await scannerBuildsTreeWithoutFollowingSymlinks()
        try await diagnosticCountersTrackScannerWork()
        try await liveScanProgressPublishesPreviewAndMappedBytes()
        try await countsOnlyProgressMatchesLiveResultWithoutPreviewMaintenance()
        try await providerMatchingOnlyExaminesDirectories()
        try bulkDirectoryReaderReturnsMetadataWithoutFollowingSymlinks()
        try bulkDirectoryReaderCanSkipModificationDates()
        try bulkDirectoryReaderReusesBoundedBuffersAtSupportedSizes()
        try bulkDirectoryReaderStreamsAndStopsEarly()
        try await largeDirectoriesKeepABoundedResultTree()
        try await cancellationStopsTheScannerWorker()
        try await stalledProviderSubtreeIsSkipped()
        try await scannerReadsSiblingDirectoriesInParallel()
        try await multipleScannersShareTraversalBudget()
        try await aiCodingAnalyzerClassifiesBeforeCompaction()
        try await aiCodingAnalyzerDeduplicatesOverlappingRoots()
        try await aiCodingAnalyzerRetainsKnownNestedRoot()
        try aiCodingAnnotationsHideInheritedContext()
        try claudeProjectDisplayNamesAreReadable()
        try openCodeCatalogResolvesXDGAndCategories()
        try t3CodeCatalogResolvesRootsAndCategories()
        try await aiCodingInstallationsReadStaticMetadata()
        try aiCodingReportKeepsMeasuredDescendantOfUnavailableRoot()
        try await aiCodingAnalyzerSkipsLinkedRoots()
        try await developerStorageDiscoversSupportedProjectArtifacts()
        try await developerStorageDeduplicatesHardLinkedFiles()
        try brandLogosExistForEveryCatalogEntry()
        try brandLogosIdentifyProductsAndStorageItems()
        try storageDescriptionsMatchOnlyKnownLocations()
        try scanCoordinatorQueuesWithoutCancellingOtherWork()
        try scanFactsAreCompleteAndDealtWithoutRepeats()
        try scanEverythingPlanPrioritizesStartupAndSkipsNetworkVolumes()
        try fullDiskAccessIsCheckedBeforeEveryActivity()
        try elapsedTimeFormattingIsReadable()
        try scanScopeStaysInsideTheSelectedVolume()
        try layoutPreservesHierarchyAndProportion()
        try layoutLeavesRequestedFreeSpaceOpen()
        try layoutRespectsDepthLimit()
        try sceneReusesLayoutForHitTesting()
        try interactiveSceneGroupsSmallItemsAndHonorsItsBudget()
        try layoutPolicyUsesFixedCompactColumnWidths()
        try fileNodeEqualityUsesImmutableArenaIdentity()
        try sessionStoreRetainsAndReplacesVolumeResults()
        try previousScanSummaryIsBoundedAndPersistent()
        try navigationHistoryRetracesVisitsAndPrunesRemovedLocations()
        print("SpaceLens self-tests passed (42/42)")
    }

    private static func navigationHistoryRetracesVisitsAndPrunesRemovedLocations() throws {
        var history = NavigationHistory<String>()
        history.record(from: "disk", to: "folder")
        history.record(from: "folder", to: "nested")
        history.record(from: "nested", to: "nested")
        history.record(from: "nested", to: "disk") // A breadcrumb jump is a visit too.
        guard history.goBack() == "nested", history.goBack() == "folder" else {
            throw SelfTestFailure.failed("Back did not retrace folders and breadcrumb visits")
        }
        history.record(from: "folder", to: "analysis")
        history.removeAll { $0 == "folder" }
        guard history.goBack() == "disk", !history.canGoBack, history.goBack() == nil else {
            throw SelfTestFailure.failed("Removed locations or duplicate selections remained in Back history")
        }
    }

    private static func scanEverythingPlanPrioritizesStartupAndSkipsNetworkVolumes() throws {
        func volume(
            _ name: String,
            path: String,
            uuid: String,
            isExternal: Bool = false,
            isLocal: Bool = true
        ) -> VolumeInfo {
            VolumeInfo(
                url: URL(fileURLWithPath: path, isDirectory: true),
                name: name,
                totalCapacity: 100,
                availableCapacity: 50,
                isExternal: isExternal,
                isReadOnly: false,
                uuid: uuid,
                isLocal: isLocal
            )
        }

        let startup = volume("Macintosh HD", path: "/", uuid: "startup")
        let external = volume(
            "External",
            path: "/Volumes/External",
            uuid: "external",
            isExternal: true
        )
        let duplicate = volume(
            "External duplicate",
            path: "/Volumes/External Duplicate",
            uuid: "external",
            isExternal: true
        )
        let network = volume(
            "Server",
            path: "/Volumes/Server",
            uuid: "network",
            isExternal: true,
            isLocal: false
        )
        let plan = ScanEverythingPlan(
            volumes: [external, network, duplicate, startup],
            analyses: ScanEverythingAnalysis.allCases
        )

        try expect(plan.volumes == [startup, external], "Scan Everything did not normalize volumes")
        try expect(
            plan.steps == [
                .volume(startup),
                .volume(external),
                .analysis(.aiCodingTools),
                .analysis(.aiModelsAndRuntimes),
                .analysis(.developerStorage)
            ],
            "Scan Everything did not place all volumes before analyses"
        )
    }

    private static func developerStorageDiscoversSupportedProjectArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensDeveloperStorage-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let projects = root.appendingPathComponent("projects", isDirectory: true)
        let project = projects.appendingPathComponent("mixed-project", isDirectory: true)
        let nodeModules = project.appendingPathComponent("node_modules", isDirectory: true)
        let orphanModules = projects.appendingPathComponent("orphan/node_modules", isDirectory: true)
        let extensionRoot = home.appendingPathComponent(".vscode/extensions/example.extension", isDirectory: true)
        let extensionModules = extensionRoot.appendingPathComponent("node_modules", isDirectory: true)
        let antigravityRoot = home.appendingPathComponent(
            ".antigravity-ide/extensions/example.extension/out/client",
            isDirectory: true
        )
        let antigravityModules = antigravityRoot.appendingPathComponent("node_modules", isDirectory: true)
        let nPrefix = projects.appendingPathComponent("n-prefix", isDirectory: true)
        let globalModules = nPrefix.appendingPathComponent("lib/node_modules", isDirectory: true)
        let emptyProject = projects.appendingPathComponent("empty-project", isDirectory: true)
        let emptyModules = emptyProject.appendingPathComponent("node_modules", isDirectory: true)
        let environment = project.appendingPathComponent(".venv", isDirectory: true)
        let mavenTarget = project.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphanModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extensionModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: antigravityModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: globalModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyModules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: environment.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: mavenTarget, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data("{}".utf8).write(to: extensionRoot.appendingPathComponent("package.json"))
        try Data("{}".utf8).write(to: antigravityRoot.appendingPathComponent("package.json"))
        try Data("{}".utf8).write(to: emptyProject.appendingPathComponent("package.json"))
        try Data("[project]".utf8).write(to: project.appendingPathComponent("pyproject.toml"))
        try Data("<project/>".utf8).write(to: project.appendingPathComponent("pom.xml"))
        try Data("home = /usr/bin".utf8).write(to: environment.appendingPathComponent("pyvenv.cfg"))
        try Data("python".utf8).write(to: environment.appendingPathComponent("bin/python"))
        try Data(repeating: 0x31, count: 8_192).write(to: nodeModules.appendingPathComponent("package.bin"))
        try Data(repeating: 0x30, count: 8_192).write(to: orphanModules.appendingPathComponent("package.bin"))
        try Data(repeating: 0x35, count: 8_192).write(to: extensionModules.appendingPathComponent("package.bin"))
        try Data(repeating: 0x37, count: 8_192).write(to: antigravityModules.appendingPathComponent("package.bin"))
        try Data(repeating: 0x36, count: 8_192).write(to: globalModules.appendingPathComponent("package.bin"))
        try Data(repeating: 0x32, count: 8_192).write(to: environment.appendingPathComponent("runtime.bin"))
        try Data(repeating: 0x33, count: 8_192).write(to: mavenTarget.appendingPathComponent("classes.jar"))
        try Data(repeating: 0x34, count: 8_192).write(to: project.appendingPathComponent("source.bin"))

        let request = DeveloperStorageRequest(
            homeDirectory: home,
            environment: ["N_PREFIX": nPrefix.path],
            automaticProjectContainers: [home, projects],
            projectContainers: []
        )
        let report = try await DeveloperStorageAnalyzer().analyze(request: request)
        let node = report.ecosystems.first(where: { $0.id == .nodeAndWeb })

        try expect(
            node?.projects.map(\.url) == [project.standardizedFileURL],
            "Developer Storage promoted markerless node_modules to a project"
        )
        try expect(
            node?.unattributedLocations.map(\.url) == [orphanModules.standardizedFileURL],
            "Developer Storage did not retain markerless dependencies as unattributed"
        )
        try expect(
            Set(node?.toolManagedLocations.map(\.url) ?? []) == Set([
                extensionModules.standardizedFileURL,
                antigravityModules.standardizedFileURL
            ]),
            "Developer Storage did not classify editor and Antigravity dependencies as tool-managed"
        )
        try expect(
            node?.sharedLocations.contains(where: { $0.url == globalModules.standardizedFileURL }) == true,
            "Developer Storage did not classify N_PREFIX global packages as shared"
        )
        try expect(
            report.ecosystems.first(where: { $0.id == .python })?.projectSize ?? 0 > 0,
            "Developer Storage did not recognize a validated Python environment"
        )
        try expect(
            report.ecosystems.first(where: { $0.id == .javaAndJVM })?.projectSize ?? 0 > 0,
            "Developer Storage did not recognize a Maven target"
        )
        try expect(
            node?.projects.contains(where: { $0.url == emptyProject.standardizedFileURL }) == false,
            "Developer Storage retained an empty measured project artifact"
        )
        try expect(report.locationCount == 7, "Developer Storage did not preserve every ownership class")

        let boundedDiscovery = try await DiskScanner().scanForDirectories(
            url: projects,
            pruningDirectoryNames: [],
            budget: DirectoryDiscoveryBudget(
                maximumDepth: 0,
                maximumDirectories: 100,
                maximumDuration: 5
            ),
            onItem: { _ in }
        )
        try expect(
            boundedDiscovery.wasTruncated,
            "Developer Storage discovery did not report a reached depth budget"
        )
    }

    private static func developerStorageDeduplicatesHardLinkedFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensDeveloperLinks-\(UUID().uuidString)", isDirectory: true)
        let shared = root.appendingPathComponent("shared", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sharedFile = shared.appendingPathComponent("package.bin")
        let projectFile = project.appendingPathComponent("package.bin")
        try Data(repeating: 0x41, count: 16_384).write(to: sharedFile)
        try FileManager.default.linkItem(at: sharedFile, to: projectFile)
        let descriptors = [
            DeveloperArtifactDescriptor(
                ecosystemID: .nodeAndWeb,
                scope: .shared,
                kind: .sharedCaches,
                name: "Shared store",
                url: shared
            ),
            DeveloperArtifactDescriptor(
                ecosystemID: .nodeAndWeb,
                scope: .project,
                kind: .projectDependencies,
                name: "Project dependencies",
                url: project,
                projectURL: project
            )
        ]
        let request = DeveloperStorageRequest(homeDirectory: root, environment: [:], projectContainers: [])
        let report = try await DeveloperStorageAnalyzer(descriptors: descriptors).analyze(request: request)
        let ecosystem = report.ecosystems.first { $0.id == .nodeAndWeb }

        try expect(report.referencedSize > report.totalSize, "Hard-linked package bytes were counted twice as unique")
        try expect(ecosystem?.sharedSize ?? 0 > 0, "Shared package store did not receive primary attribution")
        try expect(ecosystem?.projectSize == 0, "Project hard link retained duplicate unique bytes")
    }

    private static func layoutPolicyUsesFixedCompactColumnWidths() throws {
        try expect(AppLayoutMetrics.sidebarWidth == 248, "Sidebar width should remain fixed")
        try expect(
            AppLayoutMetrics.preferredInspectorWidth == 240,
            "Inspector should be approximately 30% narrower than its previous 340-point width"
        )
        try expect(
            AppLayoutMetrics.analysisListColumnWidth == 250,
            "Analysis list columns should match the narrow Tools width"
        )
    }

    private static func scanFactsAreCompleteAndDealtWithoutRepeats() throws {
        var seen: Set<String> = []
        for topic in ScanFactTopic.allCases {
            let facts = ScanFactCatalog.facts(for: topic)
            try expect(
                facts.count == ScanFactTopic.factsPerTopic,
                "\(topic.title) should have \(ScanFactTopic.factsPerTopic) facts, found \(facts.count)"
            )
            for fact in facts {
                try expect(seen.insert(fact.text).inserted, "Duplicate fact: \(fact.text)")
                try expect(fact.text.count <= ScanFact.maximumLength, "Fact too long: \(fact.text)")
                try expect(!fact.source.isEmpty, "Fact has no source: \(fact.text)")
            }
        }

        let now = Date()
        try expect(
            ScanFact.revealDelay(startedAt: now, now: now) == ScanFact.revealThreshold,
            "Facts should wait before covering a refresh that just started"
        )
        try expect(
            ScanFact.revealDelay(startedAt: nil, now: now) == 0,
            "Facts should cover queued work immediately"
        )

        var generator = SystemRandomNumberGenerator()
        var deck = ScanFactDeck(factCount: 50)
        for _ in 0..<3 {
            let round = (0..<50).map { _ in deck.deal(using: &generator) }
            try expect(Set(round).count == 50, "A fact repeated before the deck was exhausted")
        }
    }

    @MainActor
    private static func scanCoordinatorQueuesWithoutCancellingOtherWork() throws {
        let coordinator = ScanCoordinator(maximumConcurrentActivities: 2)
        let storageID = UUID()
        let analysisID = UUID()
        let batchID = UUID()
        var started: [String] = []

        coordinator.enqueue(.storage, id: storageID) { started.append("storage") }
        coordinator.enqueue(.aiCodingTools, id: analysisID) { started.append("analysis") }
        coordinator.enqueue(.scanEverything, id: batchID) { started.append("batch") }
        try expect(
            started == ["storage", "analysis"],
            "Scan coordinator did not run independent work in parallel"
        )
        try expect(
            coordinator.queuedActivities == [.scanEverything],
            "Scan coordinator did not queue work beyond its limit"
        )

        coordinator.finish(.developerStorage, id: UUID())
        try expect(started.count == 2, "A stale completion started queued work")

        coordinator.finish(.storage, id: storageID)
        try expect(
            started == ["storage", "analysis", "batch"],
            "Scan coordinator did not start queued work when a slot opened"
        )
        coordinator.finish(.aiCodingTools, id: analysisID)
        coordinator.finish(.scanEverything, id: batchID)
        try expect(
            coordinator.runningActivities.isEmpty && coordinator.queuedActivities.isEmpty,
            "Scan coordinator did not finish its work"
        )
    }

    private static func aiCodingAnalyzerClassifiesBeforeCompaction() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensAIClassification-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<(DiskScanner.retainedChildLimit + 12) {
            try Data(repeating: UInt8(index % 255), count: 1_024)
                .write(to: sessions.appendingPathComponent("session-\(index).jsonl"))
        }
        try Data(repeating: 0x41, count: 8_192)
            .write(to: cache.appendingPathComponent("index.bin"))

        let toolID = AICodingToolID(rawValue: "self-test-agent")
        let descriptor = AICodingRootDescriptor(
            toolID: toolID,
            name: "Self-test agent",
            url: root,
            explanation: "Self-test fixture",
            defaultCategory: .other,
            rules: [
                .init("sessions", category: .conversations),
                .init("cache", category: .caches)
            ]
        )
        let request = aiCodingRequest(at: root)
        let report = try await AICodingToolsAnalyzer(rootDescriptors: [descriptor])
            .analyze(request: request)
        let baseline = try await DiskScanner().scan(url: root)
        guard let tool = report.tools.first(where: { $0.id == toolID }) else {
            throw SelfTestFailure.failed("AI coding analyzer omitted a catalog-defined tool")
        }

        try expect(tool.size == baseline.root.size, "AI category bytes did not match scanner bytes")
        try expect(tool.itemCount == baseline.itemsScanned, "AI category item count lost compacted items")
        try expect(
            tool.categories.contains(where: { $0.category == .conversations }),
            "AI analyzer did not classify conversation storage"
        )
        try expect(
            tool.categories.contains(where: { $0.category == .caches }),
            "AI analyzer did not classify cache storage"
        )
        try expect(
            baseline.diagnostics.discardedNodes > 0,
            "AI compaction fixture did not exercise bounded child retention"
        )
    }

    private static func aiCodingAnnotationsHideInheritedContext() throws {
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
                )
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

        try expect(
            location.annotation(for: projects).visibleCategory == .conversations,
            "AI component root lost its visible category"
        )
        let projectAnnotation = location.annotation(for: project)
        try expect(projectAnnotation.visibleCategory == nil, "Inherited AI category remained visible")
        try expect(projectAnnotation.visibleExplanation == nil, "Inherited AI explanation remained visible")
        try expect(
            projectAnnotation.displayName == "Project (-Users-fixture-Project)",
            "AI node display-name override was not applied"
        )
    }

    private static func claudeProjectDisplayNamesAreReadable() throws {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let projectsDirectory = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let projectPath = "/Users/fixture/Documents/projects/event-omnitool"
        let encodedName = ClaudeProjectDisplayNames.encodedDirectoryName(for: projectPath)
        let displayNames = ClaudeProjectDisplayNames.overrides(
            projectDirectory: projectsDirectory,
            directoryNames: [encodedName],
            registeredProjectPaths: [projectPath],
            homeDirectory: home
        )
        let encodedPath = projectsDirectory
            .appendingPathComponent(encodedName, isDirectory: true)
            .standardizedFileURL.path

        try expect(
            displayNames[encodedPath] == "event-omnitool (\(encodedName))",
            "Claude project directory did not use its registered project basename"
        )
    }

    private static func aiCodingAnalyzerDeduplicatesOverlappingRoots() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensAIOverlap-\(UUID().uuidString)", isDirectory: true)
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
                explanation: "Self-test parent",
                defaultCategory: .other,
                rules: []
            ),
            AICodingRootDescriptor(
                toolID: .cursor,
                name: "Nested",
                url: nested,
                explanation: "Self-test nested root",
                defaultCategory: .worktrees,
                rules: []
            ),
            AICodingRootDescriptor(
                toolID: .codex,
                name: "Same physical root",
                url: root,
                explanation: "Self-test exact overlap",
                defaultCategory: .artifacts,
                rules: []
            )
        ]
        let report = try await AICodingToolsAnalyzer(rootDescriptors: descriptors)
            .analyze(request: aiCodingRequest(at: root))
        let baseline = try await DiskScanner().scan(url: root)
        guard let tool = report.tools.first(where: { $0.id == .cursor }) else {
            throw SelfTestFailure.failed("AI overlap report omitted Cursor")
        }

        try expect(tool.size == baseline.root.size, "Overlapping AI roots double-counted bytes")
        try expect(tool.itemCount == baseline.itemsScanned, "Overlapping AI roots double-counted items")
        try expect(tool.locations.count == 1, "Nested AI roots were shown as separate locations")
        try expect(
            tool.locations.first?.root?.node(at: nested) != nil,
            "Nested AI root was not retained inside its parent tree"
        )
        try expect(
            report.tools.first(where: { $0.id == .codex })?.size == baseline.root.size,
            "Shared physical root was not associated with each matching tool"
        )
        try expect(report.totalSize == baseline.root.size, "Cross-tool roots double-counted bytes")
    }

    private static func aiCodingAnalyzerRetainsKnownNestedRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensAIPriority-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("known-tool-root", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<(DiskScanner.retainedChildLimit + 8) {
            try Data(repeating: 0x41, count: 4_096)
                .write(to: root.appendingPathComponent("large-\(index).bin"))
        }
        try Data([0x42]).write(to: nested.appendingPathComponent("small.bin"))

        let descriptors = [
            AICodingRootDescriptor(
                toolID: .cursor,
                name: "Parent",
                url: root,
                explanation: "Self-test parent",
                defaultCategory: .other,
                rules: []
            ),
            AICodingRootDescriptor(
                toolID: .codex,
                name: "Known nested root",
                url: nested,
                explanation: "Self-test nested root",
                defaultCategory: .configuration,
                rules: []
            )
        ]
        let report = try await AICodingToolsAnalyzer(rootDescriptors: descriptors)
            .analyze(request: aiCodingRequest(at: root))
        let cursorRoot = report.tools.first(where: { $0.id == .cursor })?.locations.first?.root
        let codexRoot = report.tools.first(where: { $0.id == .codex })?.locations.first?.root

        try expect(
            cursorRoot?.node(at: nested) != nil,
            "Known nested AI root was discarded by compact tree retention"
        )
        try expect(
            codexRoot?.url.standardizedFileURL == nested.standardizedFileURL,
            "Nested tool did not receive its filesystem subtree"
        )
        try expect(
            cursorRoot?.children.contains(where: { $0.isAggregate }) == true,
            "Priority-retention fixture did not preserve a smaller-items aggregate"
        )
    }

    private static func openCodeCatalogResolvesXDGAndCategories() throws {
        let home = URL(fileURLWithPath: "/Users/self-test", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let customDataBase = URL(fileURLWithPath: "/Volumes/OpenCodeSelfTest", isDirectory: true)
        let project = home.appendingPathComponent("Project", isDirectory: true)
        let request = AICodingToolsRequest(
            homeDirectory: home,
            applicationSupportDirectory: appSupport,
            environment: ["XDG_DATA_HOME": customDataBase.path],
            projectRoots: [project]
        )
        let definitions = AICodingToolsCatalog.definitions(for: request)
        guard let definition = definitions.first(where: { $0.metadata.id == .openCode }) else {
            throw SelfTestFailure.failed("OpenCode is missing from the AI coding tools catalog")
        }
        let roots = definition.roots
        let defaultDataURL = home.appendingPathComponent(".local/share/opencode")
        let customDataURL = customDataBase.appendingPathComponent("opencode")

        try expect(
            definitions.map(\.metadata.id) == [.cursor, .claudeCode, .codex, .antigravity, .openCode, .t3Code],
            "AI coding tool catalog order does not include OpenCode and T3 Code"
        )
        try expect(
            roots.contains(where: {
                $0.url.standardizedFileURL.path == defaultDataURL.standardizedFileURL.path
            }),
            "OpenCode default data root is missing"
        )
        try expect(
            roots.contains(where: {
                $0.url.standardizedFileURL.path == customDataURL.standardizedFileURL.path
            }),
            "OpenCode XDG data root is missing"
        )
        try expect(
            roots.contains(where: {
                $0.url.standardizedFileURL.path
                    == project.appendingPathComponent(".opencode").standardizedFileURL.path
            }),
            "OpenCode selected-project root is missing"
        )
        guard let data = roots.first(where: {
            $0.url.standardizedFileURL.path == defaultDataURL.standardizedFileURL.path
        }) else {
            throw SelfTestFailure.failed("OpenCode data rules could not be tested")
        }
        try expect(
            data.category(for: data.url.appendingPathComponent("opencode.db-wal")) == .conversations,
            "OpenCode database sidecar was not classified as session data"
        )
        try expect(
            data.category(for: data.url.appendingPathComponent("snapshot/repo")) == .recovery,
            "OpenCode snapshots were not classified as recovery data"
        )
        try expect(
            data.category(for: data.url.appendingPathComponent("worktree/repo")) == .worktrees,
            "OpenCode worktrees were not classified as checkouts"
        )
        try expect(
            !roots.contains(where: { $0.url.path.contains("/.claude") }),
            "OpenCode catalog incorrectly claims Claude compatibility data"
        )
    }

    private static func t3CodeCatalogResolvesRootsAndCategories() throws {
        let home = URL(fileURLWithPath: "/Users/self-test", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let customHome = URL(fileURLWithPath: "/Volumes/T3SelfTest", isDirectory: true)
        let definition = T3CodeCatalog.definition(for: AICodingToolsRequest(
            homeDirectory: home,
            applicationSupportDirectory: appSupport,
            environment: ["T3CODE_HOME": customHome.path],
            projectRoots: []
        ))
        func root(_ url: URL) -> AICodingRootDescriptor? {
            definition.roots.first {
                $0.url.standardizedFileURL.path == url.standardizedFileURL.path
            }
        }

        guard let data = root(home.appendingPathComponent(".t3")),
              let application = root(appSupport.appendingPathComponent("t3code-v2")) else {
            throw SelfTestFailure.failed("T3 Code default roots are missing")
        }
        try expect(root(customHome) != nil, "T3 Code custom home root is missing")
        try expect(
            data.category(for: data.url.appendingPathComponent("userdata/statev2.sqlite-wal")) == .conversations,
            "T3 Code database sidecar was not classified as session data"
        )
        try expect(
            data.category(for: data.url.appendingPathComponent("worktrees/repo/branch")) == .worktrees,
            "T3 Code worktrees were not classified as checkouts"
        )
        try expect(
            data.category(for: data.url.appendingPathComponent("userdata/logs/server.trace.ndjson")) == .logs,
            "T3 Code logs were not classified as diagnostics"
        )
        try expect(
            application.category(for: application.url.appendingPathComponent("GraphiteDawnCache/data")) == .caches,
            "T3 Code render caches were not classified as caches"
        )
        try expect(
            definition.roots.filter { !$0.reportsWhenMissing }.count == 6,
            "T3 Code optional roots should stay hidden when absent"
        )
    }

    private static func aiCodingInstallationsReadStaticMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensInstallations-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let app = applications.appendingPathComponent("Cursor.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "com.todesktop.230313mzl4w4u92",
                "CFBundleShortVersionString": "3.19.19",
                "CFBundleVersion": "31919"
            ],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let releases = home.appendingPathComponent(".local/share/claude/versions")
        let active = releases.appendingPathComponent("2.1.223")
        let previous = releases.appendingPathComponent("2.1.221")
        let bin = home.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: releases, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data([0x01]).write(to: active)
        try Data([0x01]).write(to: previous)
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("claude"),
            withDestinationURL: active
        )

        let request = AICodingToolsRequest(
            homeDirectory: home,
            applicationSupportDirectory: home.appendingPathComponent("Library/Application Support"),
            environment: ["PATH": bin.path],
            projectRoots: [],
            applicationDirectories: [applications]
        )
        let installations = try await AICodingInstallationsDetector().detect(request: request)
        let cursor = installations[.cursor]?.first
        let claude = installations[.claudeCode]?.first

        try expect(cursor?.version?.value == "3.19.19", "App manifest version was not detected")
        try expect(
            cursor?.version?.source.kind == .appManifest,
            "App version did not retain manifest evidence"
        )
        try expect(claude?.version?.value == "2.1.223", "Active native CLI version was not detected")
        try expect(
            claude?.retainedReleases.count == 2,
            "Native CLI releases were counted as separate installations"
        )
        try expect(claude?.isOnProcessPath == true, "CLI PATH evidence was not retained")
    }

    private static func aiCodingReportKeepsMeasuredDescendantOfUnavailableRoot() throws {
        let parentURL = URL(fileURLWithPath: "/self-test/unavailable-agent", isDirectory: true)
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
            explanation: "Self-test fixture",
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
            explanation: "Self-test fixture",
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

        try expect(report.totalSize == 42, "Unavailable ancestor hid measured child bytes")
        try expect(report.itemCount == 1, "Unavailable ancestor hid measured child items")
        try expect(report.issueCount == 1, "Coverage issue paths were counted incorrectly")
    }

    private static func aiCodingAnalyzerSkipsLinkedRoots() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensAILink-\(UUID().uuidString)", isDirectory: true)
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let link = parent.appendingPathComponent("tool-data")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try Data(repeating: 0x41, count: 4_096)
            .write(to: target.appendingPathComponent("private.jsonl"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let descriptor = AICodingRootDescriptor(
            toolID: .claudeCode,
            name: "Linked data",
            url: link,
            explanation: "Self-test linked root",
            defaultCategory: .conversations,
            rules: []
        )
        let missingDescriptor = AICodingRootDescriptor(
            toolID: .claudeCode,
            name: "Missing data",
            url: parent.appendingPathComponent("missing"),
            explanation: "Self-test missing root",
            defaultCategory: .other,
            rules: []
        )
        let report = try await AICodingToolsAnalyzer(
            rootDescriptors: [descriptor, missingDescriptor]
        )
            .analyze(request: aiCodingRequest(at: parent))
        let locations = report.tools.first(where: { $0.id == .claudeCode })?.locations ?? []

        try expect(
            locations.contains(where: { $0.status == .linked }),
            "AI analyzer did not report a linked root"
        )
        try expect(
            locations.contains(where: { $0.status == .missing }),
            "AI analyzer did not report a missing root"
        )
        try expect(report.totalSize == 0, "AI analyzer followed a linked root")
    }

    private static func aiCodingRequest(at root: URL) -> AICodingToolsRequest {
        AICodingToolsRequest(
            homeDirectory: root,
            applicationSupportDirectory: root,
            environment: [:],
            projectRoots: []
        )
    }

    private static func fileNodeEqualityUsesImmutableArenaIdentity() throws {
        let rootURL = URL(fileURLWithPath: "/identity-self-test", isDirectory: true)
        let child = FileNode(
            url: rootURL.appendingPathComponent("child"),
            name: "child",
            size: 1,
            isDirectory: false,
            isReadable: true,
            children: []
        )
        let root = FileNode(
            url: rootURL,
            name: "identity-self-test",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: [child]
        )
        let independentlyCreatedRoot = FileNode(
            url: rootURL,
            name: root.name,
            size: root.size,
            isDirectory: root.isDirectory,
            isReadable: root.isReadable,
            children: root.children
        )

        try expect(root == root, "A node stopped comparing equal to itself")
        try expect(root != root.children[0], "Different nodes in one arena compared equal")
        try expect(
            root != independentlyCreatedRoot,
            "Nodes from different immutable arenas compared equal"
        )
    }

    private static func previousScanSummaryIsBoundedAndPersistent() throws {
        let rootURL = URL(fileURLWithPath: "/Volumes/SelfTest", isDirectory: true)
        let children = (0..<12).map { index in
            FileNode(
                url: rootURL.appendingPathComponent("Folder-\(index)"),
                name: "Folder-\(index)",
                size: Int64(index + 1),
                isDirectory: true,
                isReadable: true,
                children: [],
                itemCount: index + 1
            )
        }
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        let root = FileNode(
            url: rootURL,
            name: "SelfTest",
            size: total,
            isDirectory: true,
            isReadable: true,
            children: children,
            itemCount: children.reduce(1) { $0 + $1.itemCount }
        )
        let result = ScanResult(
            root: root,
            duration: 1,
            itemsScanned: root.itemCount,
            unreadableItems: 0
        )
        let volume = VolumeInfo(
            url: rootURL,
            name: "SelfTest",
            totalCapacity: 1_000,
            availableCapacity: 200,
            isExternal: true,
            isReadOnly: false,
            uuid: "SELF-TEST"
        )
        let summary = PreviousScanSummary(result: result, volume: volume)
        let restoredRoot = summary.makeRoot(at: rootURL)
        let restoredResult = summary.makeResult(at: rootURL)
        try expect(restoredRoot.children.count == 12, "Previous scan snapshot lost retained children")
        try expect(
            restoredRoot.children.reduce(Int64(0)) { $0 + $1.size } == total,
            "Previous scan snapshot did not preserve omitted byte totals"
        )
        try expect(restoredResult.root.url == restoredRoot.url, "Previous scan result restored the wrong root")
        try expect(restoredResult.root.size == restoredRoot.size, "Previous scan result lost its root size")
        try expect(restoredResult.duration == result.duration, "Previous scan result lost its duration")
        try expect(restoredResult.itemsScanned == result.itemsScanned, "Previous scan result lost its item count")

        var nestedChild = FileNode(
            url: rootURL.appendingPathComponent("Level-7"),
            name: "Level-7",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: []
        )
        for level in stride(from: 6, through: 1, by: -1) {
            nestedChild = FileNode(
                url: rootURL.appendingPathComponent("Level-\(level)"),
                name: "Level-\(level)",
                size: 1,
                isDirectory: true,
                isReadable: true,
                children: [nestedChild]
            )
        }
        let nestedResult = ScanResult(
            root: FileNode(
                url: rootURL,
                name: "SelfTest",
                size: 1,
                isDirectory: true,
                isReadable: true,
                children: [nestedChild]
            ),
            duration: 1,
            itemsScanned: 8,
            unreadableItems: 0
        )
        var restoredNestedNode = PreviousScanSummary(
            result: nestedResult,
            volume: volume
        ).makeRoot(at: rootURL)
        for level in 1...6 {
            guard let child = restoredNestedNode.children.first else {
                throw SelfTestFailure.failed("Previous scan snapshot lost chart level \(level)")
            }
            restoredNestedNode = child
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensSummarySelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PreviousScanStore(fileURL: directory.appendingPathComponent("summary.json"))
        try store.store(summary)
        try expect(
            store.load()[volume.persistentIdentifier] == summary,
            "Previous scan snapshot did not round-trip"
        )
    }

    private static func scannerBuildsTreeWithoutFollowingSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensSelfTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(repeating: 0x41, count: 128 * 1024)
            .write(to: nested.appendingPathComponent("large.bin"))
        try Data(repeating: 0x42, count: 4 * 1024)
            .write(to: root.appendingPathComponent("small.bin"))
        try FileManager.default.createSymbolicLink(
            at: nested.appendingPathComponent("loop"),
            withDestinationURL: root
        )

        let result = try await DiskScanner().scan(url: root)
        try expect(result.root.children.count == 2, "Scanner did not build the expected root children")
        try expect(result.root.children.first?.name == "Nested", "Scanner did not sort children by size")

        let symlink = result.root.children
            .first(where: { $0.name == "Nested" })?
            .children
            .first(where: { $0.name == "loop" })
        try expect(symlink != nil, "Scanner omitted the symbolic link entry")
        try expect(symlink?.isDirectory == false, "Scanner followed a symbolic link as a directory")
        try expect(symlink?.children.isEmpty == true, "Symbolic link unexpectedly has descendants")
    }

    private static func liveScanProgressPublishesPreviewAndMappedBytes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensLivePreview-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        let deeper = nested.appendingPathComponent("Deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: deeper, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 8_192)
            .write(to: deeper.appendingPathComponent("payload.bin"))

        let recorder = SelfTestProgressRecorder()
        let result = try await DiskScanner().scan(url: root) { progress in
            recorder.record(progress)
        }
        let snapshots = recorder.snapshots

        try expect(
            snapshots.contains { $0.previewRoot != nil && $0.itemsScanned < result.itemsScanned },
            "Scanner did not publish a provisional tree before completion"
        )
        try expect(
            snapshots.last?.mappedBytes == result.root.size,
            "Final mapped-byte progress did not match the result"
        )
        try expect(
            (snapshots.last?.previewRoot?.storageMetrics.nodeCount ?? Int.max)
                < result.root.storageMetrics.nodeCount,
            "Final progress duplicated the complete retained result"
        )
        let mappedBytes = snapshots.map(\.mappedBytes)
        try expect(mappedBytes == mappedBytes.sorted(), "Mapped-byte progress moved backwards")
    }

    private static func countsOnlyProgressMatchesLiveResultWithoutPreviewMaintenance() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensCountsOnly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for branchIndex in 0..<12 {
            let branch = root.appendingPathComponent("Branch-\(branchIndex)", isDirectory: true)
            let nested = branch.appendingPathComponent("Nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data(repeating: UInt8(branchIndex), count: 4_096)
                .write(to: nested.appendingPathComponent("payload.bin"))
        }

        let liveRecorder = SelfTestProgressRecorder()
        let liveResult = try await DiskScanner(
            maximumParallelism: 4,
            previewPolicy: .live
        ).scan(url: root) { liveRecorder.record($0) }
        let countsOnlyRecorder = SelfTestProgressRecorder()
        let countsOnlyResult = try await DiskScanner(
            maximumParallelism: 4,
            previewPolicy: .countsOnly
        ).scan(url: root) { countsOnlyRecorder.record($0) }

        func treesMatch(_ left: FileNode, _ right: FileNode) -> Bool {
            left.url == right.url
                && left.name == right.name
                && left.size == right.size
                && left.isDirectory == right.isDirectory
                && left.isReadable == right.isReadable
                && left.itemCount == right.itemCount
                && left.directItemCount == right.directItemCount
                && left.isAggregate == right.isAggregate
                && left.children.count == right.children.count
                && zip(left.children, right.children).allSatisfy {
                    treesMatch($0.0, $0.1)
                }
        }

        try expect(
            treesMatch(countsOnlyResult.root, liveResult.root),
            "Counts-only changed the retained tree"
        )
        try expect(
            countsOnlyResult.itemsScanned == liveResult.itemsScanned,
            "Counts-only changed the scanned-item total"
        )
        try expect(
            countsOnlyRecorder.snapshots.allSatisfy { $0.previewRoot == nil },
            "Counts-only emitted a preview tree"
        )
        try expect(
            countsOnlyRecorder.snapshots.last?.mappedBytes == countsOnlyResult.root.size,
            "Counts-only final mapped bytes did not match the result"
        )
        try expect(
            countsOnlyResult.diagnostics.previewMappedByteMerges == 0
                && countsOnlyResult.diagnostics.rootPreviewBranchResolutions == 0
                && countsOnlyResult.diagnostics.completedPreviewAttempts == 0
                && countsOnlyResult.diagnostics.previewConstructions == 0,
            "Counts-only performed live-preview maintenance"
        )
        try expect(
            countsOnlyResult.diagnostics.progressMerges
                < countsOnlyResult.diagnostics.directoryCount,
            "Counts-only progress still merged at every directory"
        )
        try expect(
            countsOnlyResult.diagnostics.directoryTasks > 0
                && countsOnlyResult.diagnostics.forcedProgressFlushes
                    < countsOnlyResult.diagnostics.directoryTasks,
            "Completed child tasks still forced shared progress merges"
        )
        try expect(
            liveResult.diagnostics.rootPreviewBranchResolutions == 12
                && liveResult.diagnostics.completedPreviewAttempts == 12,
            "Live preview did not resolve only direct root branches"
        )
    }

    private static func bulkDirectoryReaderReturnsMetadataWithoutFollowingSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBulkReader-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let file = root.appendingPathComponent("file.bin")
        let link = root.appendingPathComponent("folder-link")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 4_096).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

        let entries = try BulkDirectoryReader.contents(of: root)
        let metadataByName = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                entry.metadata.map { ($0.name, $0) }
            }
        )

        try expect(metadataByName["Folder"]?.kind == .directory, "Bulk reader lost directory metadata")
        try expect(metadataByName["file.bin"]?.kind == .regular, "Bulk reader lost regular-file metadata")
        try expect((metadataByName["file.bin"]?.size ?? 0) > 0, "Bulk reader lost allocated file size")
        try expect(
            metadataByName["file.bin"]?.modificationDate != nil,
            "Bulk reader lost modification time"
        )
        try expect(metadataByName["folder-link"]?.kind == .symbolicLink, "Bulk reader followed a symbolic link")
        try expect(metadataByName.values.allSatisfy { $0.identity != nil }, "Bulk reader lost device/inode identities")
    }

    private static func bulkDirectoryReaderCanSkipModificationDates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBulkReaderNoDates-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("file.bin")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 4_096).write(to: file)

        let pool = BulkDirectoryBufferPool(
            capacity: 1,
            bufferSize: BulkDirectoryReader.defaultBufferSize,
            includeModificationDate: false
        )
        let metadata = try BulkDirectoryReader.contents(of: root, using: pool).first?.metadata

        try expect(metadata?.modificationDate == nil, "Bulk reader returned an unrequested modification time")
        try expect((metadata?.size ?? 0) > 0, "Bulk reader lost size while omitting modification time")
        try expect(metadata?.identity != nil, "Bulk reader lost identity while omitting modification time")
    }

    private static func diagnosticCountersTrackScannerWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("first.bin"))
        try Data([0x42]).write(to: root.appendingPathComponent("second.bin"))

        let scanner = DiskScanner(directoryReader: { url, keys in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: []
            )
        })
        let result = try await scanner.scan(url: root)

        try expect(result.diagnostics.syscallBatches == 0, "Custom reader recorded bulk syscall batches")
        try expect(result.diagnostics.fallbackLstatCalls == 2, "Fallback lstat calls were not counted")
        try expect(result.diagnostics.bufferAllocations == 0, "Custom reader allocated a bulk buffer")
        try expect(result.diagnostics.directoryTasks == 0, "Flat scan created a directory task")
        try expect(result.diagnostics.directoryCount == 1, "Directory count did not include the scan root")
        try expect(result.diagnostics.retainedNodes == 2, "Retained node decisions were not counted")
        try expect(result.diagnostics.discardedNodes == 0, "Flat scan discarded a node")
        try expect(result.diagnostics.progressEmissions >= 2, "Progress emissions were not counted")
        try expect(result.diagnostics.retainedArenaNodeCount == 3, "Retained arena nodes were not counted")
        try expect(
            result.diagnostics.arenaConstructionDurationSeconds > 0,
            "Arena construction duration was not measured"
        )
        try expect(
            result.diagnostics.rssBeforeArenaConstructionBytes > 0
                && result.diagnostics.rssAfterArenaConstructionBytes > 0,
            "Arena RSS boundaries were not measured"
        )
    }

    private static func providerMatchingOnlyExaminesDirectories() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensProviderMatching-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        let file = root.appendingPathComponent("file.bin")
        let link = root.appendingPathComponent("file-link")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let probe = ProviderMatchingProbe()
        let scanner = DiskScanner(shouldIsolateSubtree: { url in
            probe.record(url)
            return false
        })
        _ = try await scanner.scan(url: root)

        try expect(
            Set(probe.recordedPaths) == Set([root.standardizedFileURL.path, nested.path]),
            "Provider matching examined a regular file or symbolic link"
        )
    }

    private static func bulkDirectoryReaderReusesBoundedBuffersAtSupportedSizes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBufferPool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        for bufferSize in [32, 64, 256].map({ $0 * 1024 }) {
            let pool = BulkDirectoryBufferPool(capacity: 2, bufferSize: bufferSize)
            for _ in 0..<3 {
                let entries = try BulkDirectoryReader.contents(of: root, using: pool)
                try expect(
                    entries.compactMap(\.metadata?.name) == ["file.bin"],
                    "Bulk reader changed results at \(bufferSize / 1024) KB"
                )
            }
            try expect(pool.bufferSize == bufferSize, "Bulk reader changed the configured buffer size")
            try expect(pool.pooledBufferCount == 1, "Bulk reader did not reuse its pooled buffer")
            try expect(pool.allocationCount == 1, "Bulk reader allocated a buffer per directory read")
        }

        let boundedPool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 32 * 1024)
        boundedPool.withBuffer { _, _ in
            boundedPool.withBuffer { _, _ in
                // The second concurrent lease is deliberately unpooled so a
                // timed-out provider syscall cannot block unrelated reads.
            }
        }
        try expect(
            boundedPool.pooledBufferCount == boundedPool.capacity,
            "Bulk reader retained more buffers than its configured capacity"
        )
    }

    private static func bulkDirectoryReaderStreamsAndStopsEarly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensStreamingReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<500 {
            _ = FileManager.default.createFile(
                atPath: root.appendingPathComponent("file-\(index).bin").path,
                contents: Data([UInt8(index % 255)])
            )
        }

        let completeDiagnostics = ScanDiagnosticCounters()
        let completePool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 4 * 1024)
        var completeCount = 0
        try BulkDirectoryReader.forEachEntry(
            of: root,
            using: completePool,
            diagnostics: completeDiagnostics
        ) { _ in
            completeCount += 1
        }
        try expect(completeCount == 500, "Streaming reader omitted directory entries")
        try expect(
            completeDiagnostics.snapshot(bufferAllocations: completePool.allocationCount).syscallBatches > 1,
            "Streaming fixture did not span multiple kernel batches"
        )

        let stoppedDiagnostics = ScanDiagnosticCounters()
        let stoppedPool = BulkDirectoryBufferPool(capacity: 1, bufferSize: 4 * 1024)
        var stoppedCount = 0
        do {
            try BulkDirectoryReader.forEachEntry(
                of: root,
                using: stoppedPool,
                diagnostics: stoppedDiagnostics
            ) { _ in
                stoppedCount += 1
                throw StopDirectoryStreaming()
            }
            throw SelfTestFailure.failed("Streaming reader ignored callback termination")
        } catch is StopDirectoryStreaming {
            // Expected.
        }
        try expect(stoppedCount == 1, "Streaming reader materialized entries before callback delivery")
        try expect(
            stoppedDiagnostics.snapshot(bufferAllocations: stoppedPool.allocationCount).syscallBatches == 1,
            "Streaming reader fetched a later batch after callback termination"
        )
    }

    private static func layoutPreservesHierarchyAndProportion() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let deep = node("deep", size: 25, at: rootURL.appendingPathComponent("large/deep"))
        let large = node("large", size: 75, at: rootURL.appendingPathComponent("large"), children: [deep])
        let small = node("small", size: 25, at: rootURL.appendingPathComponent("small"))
        let root = node("test", size: 100, at: rootURL, children: [large, small])
        let segments = SunburstLayout.segments(for: root, maxDepth: 4, minimumAngularSpan: 0)

        guard let largeSegment = segments.first(where: { $0.node?.name == "large" }),
              let smallSegment = segments.first(where: { $0.node?.name == "small" }),
              let deepSegment = segments.first(where: { $0.node?.name == "deep" }) else {
            throw SelfTestFailure.failed("Layout omitted expected segments")
        }

        try expect(deepSegment.depth == 1, "Layout lost the child depth")
        let ratio = largeSegment.angularSpan / smallSegment.angularSpan
        try expect(abs(ratio - 3) < 0.001, "Layout angles are not proportional to byte size")
    }

    private static func layoutLeavesRequestedFreeSpaceOpen() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let first = node("first", size: 60, at: rootURL.appendingPathComponent("first"))
        let second = node("second", size: 40, at: rootURL.appendingPathComponent("second"))
        let root = node("test", size: 100, at: rootURL, children: [first, second])
        let segments = SunburstLayout.segments(
            for: root,
            maxDepth: 2,
            minimumAngularSpan: 0,
            angularExtent: .pi * 1.5
        )

        let furthestAngle = segments.map(\.endAngle).max() ?? 0
        try expect(
            abs(furthestAngle - (.pi * 1.5)) < 0.001,
            "Layout filled the free-space sector instead of leaving it open"
        )
    }

    private static func sceneReusesLayoutForHitTesting() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let large = node("large", size: 75, at: rootURL.appendingPathComponent("large"))
        let small = node("small", size: 25, at: rootURL.appendingPathComponent("small"))
        let root = node("test", size: 100, at: rootURL, children: [large, small])
        let scene = SunburstScene(root: root, maxDepth: 4, minimumAngularSpan: 0)

        try expect(scene.segments.count == 2, "Chart scene omitted expected segments")
        for _ in 0..<1_000 {
            try expect(
                scene.segmentIndex(atDepth: 0, angle: .pi)
                    .flatMap { scene.segments[$0].node?.name } == "large",
                "Chart scene hit testing changed across repeated lookups"
            )
        }
    }

    private static func interactiveSceneGroupsSmallItemsAndHonorsItsBudget() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let large = node("large", size: 950, at: rootURL.appendingPathComponent("large"))
        let small = (0..<10).map { index in
            node("small-\(index)", size: 5, at: rootURL.appendingPathComponent("small-\(index)"))
        }
        let root = node("test", size: 1_000, at: rootURL, children: [large] + small)
        let scene = SunburstScene(
            root: root,
            maxDepth: 4,
            angularExtent: .pi * 2,
            interactionRadius: 200,
            policy: .interactive
        )

        guard let group = scene.segments.compactMap(\.smallerItems).first else {
            throw SelfTestFailure.failed("Interactive chart omitted the smaller-items group")
        }
        try expect(scene.segments.count == 2, "Interactive chart retained sub-percent segments")
        try expect(group.size == 50, "Interactive chart changed grouped byte totals")
        try expect(group.children.count == 10, "Interactive chart lost grouped item links")
        try expect(
            SunburstScenePolicy.interactive.minimumAngularSpan(
                angularExtent: .pi,
                interactionRadius: 100
            ) == 0.06,
            "Interactive chart did not enforce the pixel floor"
        )
    }

    private static func cancellationStopsTheScannerWorker() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x41]).write(to: root.appendingPathComponent("file.bin"))

        let gate = CancellationTestGate()
        let scanTask = Task {
            try await DiskScanner().scan(url: root) { progress in
                if progress.itemsScanned == 1 {
                    gate.markStartedAndWait()
                }
            }
        }

        for _ in 0..<200 where !gate.hasStarted {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard gate.hasStarted else {
            scanTask.cancel()
            gate.release()
            throw SelfTestFailure.failed("Scanner worker did not start")
        }

        scanTask.cancel()
        gate.release()

        do {
            _ = try await scanTask.value
            throw SelfTestFailure.failed("Cancelled scan completed successfully instead of stopping")
        } catch ScanFailure.cancelled {
            // Expected.
        }
    }

    private static func largeDirectoriesKeepABoundedResultTree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensBoundedTree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<150 {
            try Data([UInt8(index % 255)])
                .write(to: root.appendingPathComponent("file-\(index).bin"))
        }

        let result = try await DiskScanner().scan(url: root)
        try expect(result.root.children.count <= 97, "Scanner retained every file in a large directory")
        try expect(
            result.root.children.contains(where: { $0.name == "Smaller items" }),
            "Scanner did not aggregate smaller items"
        )
        try expect(result.itemsScanned == 151, "Scanner lost the real measured-item count")
        try expect(result.root.itemCount == 151, "Compacted tree lost its represented-item count")
        try expect(result.root.directItemCount == 150, "Compacted tree lost its direct-item count")
        try expect(
            result.diagnostics.progressMerges < result.itemsScanned / 4,
            "Progress totals were merged once per scanned item instead of in batches"
        )
        try expect(
            result.root.children.reduce(Int64(0), { $0 + $1.size }) == result.root.size,
            "Aggregating smaller items changed the measured byte total"
        )
        func countRetainedNodes(in node: FileNode) -> Int {
            1 + node.children.reduce(0) { $0 + countRetainedNodes(in: $1) }
        }
        try expect(
            result.root.storageMetrics.storedAbsolutePathCount == 1,
            "Retained result stored more than one absolute path"
        )
        try expect(
            result.root.storageMetrics.nodeCount == countRetainedNodes(in: result.root),
            "Compact result arena did not contain exactly the retained nodes"
        )
    }

    private static func stalledProviderSubtreeIsSkipped() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensStallWatchdog-\(UUID().uuidString)", isDirectory: true)
        let blocked = root.appendingPathComponent("Blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gate = CancellationTestGate()
        let scanner = DiskScanner(
            stalledSubtreeTimeout: 0.1,
            shouldIsolateSubtree: { $0.lastPathComponent == "Blocked" },
            directoryReader: { url, keys in
                if url.lastPathComponent == "Blocked" {
                    gate.markStartedAndWait()
                    return []
                }
                return try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            }
        )

        let start = Date()
        let result = try await scanner.scan(url: root)
        let duration = Date().timeIntervalSince(start)
        gate.release()

        try expect(gate.hasStarted, "Stall watchdog fixture never entered the blocked subtree")
        try expect(duration < 1, "Stalled subtree blocked the whole scan for \(duration) seconds")
        try expect(result.itemsScanned == 2, "Stalled subtree changed precise item accounting")
        try expect(result.unreadableItems == 1, "Stalled subtree was not counted as unreadable")
        try expect(result.diagnostics.directoryCount == 2, "Stalled provider directory was not counted")
        try expect(result.diagnostics.providerTimeouts == 1, "Provider timeout was not counted")
        try expect(result.diagnostics.abandonedWorkers == 1, "Abandoned provider worker was not counted")
        try expect(
            result.root.children.first(where: { $0.name == "Blocked" })?.isReadable == false,
            "Stalled subtree was not represented as unreadable"
        )
    }

    private static func scannerReadsSiblingDirectoriesInParallel() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensParallelScan-\(UUID().uuidString)", isDirectory: true)
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let probe = ParallelDirectoryReadProbe()
        let scanner = DiskScanner(
            maximumParallelism: 2,
            shouldIsolateSubtree: { _ in false },
            directoryReader: { url, keys in
                if url.standardizedFileURL.path == first.path
                    || url.standardizedFileURL.path == second.path {
                    probe.enterAndWaitForOverlap()
                }
                return try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            }
        )

        _ = try await scanner.scan(url: root)
        try expect(
            probe.maximumConcurrentReads >= 2,
            "Scanner reached only \(probe.maximumConcurrentReads) concurrent sibling directory read(s)"
        )
    }

    private static func multipleScannersShareTraversalBudget() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensSharedBudget-\(UUID().uuidString)", isDirectory: true)
        let firstRoot = fixtureRoot.appendingPathComponent("First", isDirectory: true)
        let secondRoot = fixtureRoot.appendingPathComponent("Second", isDirectory: true)
        for root in [firstRoot, secondRoot] {
            for index in 0..<3 {
                let branch = root.appendingPathComponent("Branch\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: branch, withIntermediateDirectories: true)
                try Data([UInt8(index)]).write(to: branch.appendingPathComponent("payload.bin"))
            }
        }
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let budget = ScanTraversalBudget(permitCount: 3)
        let scanner = DiskScanner(maximumParallelism: 3, traversalBudget: budget)
        async let first = scanner.scan(url: firstRoot)
        async let second = scanner.scan(url: secondRoot)
        let results = try await (first, second)
        let snapshot = budget.snapshot

        try expect(results.0.itemsScanned == 7, "First shared-budget scan lost items")
        try expect(results.1.itemsScanned == 7, "Second shared-budget scan lost items")
        try expect(
            snapshot.maximumObservedReaders <= 3,
            "Shared traversal budget exceeded its reader limit"
        )
        try expect(snapshot.activeReaders == 0, "Shared traversal permits leaked after success")
    }

    private static func scanScopeStaysInsideTheSelectedVolume() throws {
        let rootScope = ScanScope(rootPath: "/", rootDevice: 10, excludedPaths: [])
        try expect(
            rootScope.allows(path: "/Users/me", identity: FileIdentity(device: 10, inode: 2)),
            "Root scope rejected a logical main-disk folder"
        )
        try expect(
            !rootScope.allows(path: "/System/Volumes/Data", identity: FileIdentity(device: 10, inode: 3)),
            "Root scope allowed the duplicate APFS Data mount"
        )
        try expect(
            !rootScope.allows(path: "/Volumes/External", identity: FileIdentity(device: 11, inode: 4)),
            "Root scope crossed into an external disk"
        )

        let folderScope = ScanScope(rootPath: "/tmp/example", rootDevice: 10, excludedPaths: [])
        try expect(
            !folderScope.allows(path: "/tmp/example/mount", identity: FileIdentity(device: 11, inode: 5)),
            "Folder scope crossed a nested volume boundary"
        )
        let profilingScope = ScanScope(
            rootPath: "/",
            rootDevice: 10,
            excludedPaths: ["/Users/me/profile.trace"]
        )
        try expect(
            !profilingScope.allows(
                path: "/Users/me/profile.trace/run/data",
                identity: FileIdentity(device: 10, inode: 6)
            ),
            "Full-disk profiling recursed into its active trace bundle"
        )
    }

    private static func fullDiskAccessIsCheckedBeforeEveryActivity() throws {
        let denied = FullDiskAccessChecker(accessProbe: { false })
        let granted = FullDiskAccessChecker(accessProbe: { true })
        let exampleHome = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        try expect(
            denied.status() == .needsUserApproval,
            "A scan or analysis did not request Full Disk Access"
        )
        try expect(
            granted.status() == .granted,
            "A scan or analysis ignored available Full Disk Access"
        )
        try expect(
            denied.status() == .needsUserApproval,
            "Full Disk Access was not rechecked for the next activity"
        )
        try expect(
            FullDiskAccessChecker.protectedDatabaseURL(homeDirectory: exampleHome).path
                == "/Users/example/Library/Application Support/com.apple.TCC/TCC.db",
            "Full Disk Access used a system probe that can be readable without authorization"
        )
    }

    private static func elapsedTimeFormattingIsReadable() throws {
        try expect(
            StorageFormatters.duration(65) == "1 min 5 sec",
            "Elapsed scan time was not formatted as minutes and seconds"
        )
    }

    private static func layoutRespectsDepthLimit() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let third = node("three", size: 1, at: rootURL.appendingPathComponent("one/two/three"))
        let second = node("two", size: 1, at: rootURL.appendingPathComponent("one/two"), children: [third])
        let first = node("one", size: 1, at: rootURL.appendingPathComponent("one"), children: [second])
        let root = node("test", size: 1, at: rootURL, children: [first])
        let segments = SunburstLayout.segments(for: root, maxDepth: 2, minimumAngularSpan: 0)
        try expect(segments.map(\.depth).max() == 1, "Layout exceeded its configured depth")
    }

    private static func sessionStoreRetainsAndReplacesVolumeResults() throws {
        let firstURL = URL(fileURLWithPath: "/Volumes/First")
        let secondURL = URL(fileURLWithPath: "/Volumes/Second")
        let firstResult = ScanResult(
            root: node("First", size: 100, at: firstURL),
            duration: 2,
            itemsScanned: 5,
            unreadableItems: 0
        )
        let refreshedResult = ScanResult(
            root: node("First", size: 120, at: firstURL),
            duration: 1,
            itemsScanned: 6,
            unreadableItems: 0
        )
        let secondResult = ScanResult(
            root: node("Second", size: 40, at: secondURL),
            duration: 1,
            itemsScanned: 2,
            unreadableItems: 0
        )
        var store = ScanSessionStore()

        try expect(store.result(for: firstURL) == nil, "An unscanned disk unexpectedly had cached data")
        store.store(firstResult, for: firstURL)
        store.store(secondResult, for: secondURL)
        store.store(refreshedResult, for: firstURL)

        try expect(store.result(for: firstURL) == refreshedResult, "A rescan did not replace the cached disk result")
        try expect(store.result(for: secondURL) == secondResult, "Rescanning one disk discarded another cached result")

        store.removeResult(for: firstURL)
        try expect(store.result(for: firstURL) == nil, "Removing a session location kept its cached result")
        try expect(store.result(for: secondURL) == secondResult, "Removing one session location discarded another result")
    }

    private static func node(
        _ name: String,
        size: Int64,
        at url: URL,
        children: [FileNode] = []
    ) -> FileNode {
        FileNode(
            url: url,
            name: name,
            size: size,
            isDirectory: !children.isEmpty,
            isReadable: true,
            children: children
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestFailure.failed(message) }
    }
}

private final class CancellationTestGate: @unchecked Sendable {
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

private final class SelfTestProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ScanProgress] = []

    var snapshots: [ScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func record(_ progress: ScanProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }
}

private final class ParallelDirectoryReadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let overlapReached = DispatchSemaphore(value: 0)
    private var activeReads = 0
    private var maximumReads = 0

    var maximumConcurrentReads: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumReads
    }

    func enterAndWaitForOverlap() {
        lock.lock()
        activeReads += 1
        maximumReads = max(maximumReads, activeReads)
        if activeReads >= 2 {
            overlapReached.signal()
            overlapReached.signal()
        }
        lock.unlock()

        _ = overlapReached.wait(timeout: .now() + .milliseconds(500))

        lock.lock()
        activeReads -= 1
        lock.unlock()
    }
}

private final class ProviderMatchingProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    var recordedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func record(_ url: URL) {
        lock.lock()
        paths.append(url.path)
        lock.unlock()
    }
}
