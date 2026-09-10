import Foundation

enum OpenCodeCatalog {
    static let metadata = AICodingToolMetadata(
        id: .openCode,
        displayName: "OpenCode",
        systemImage: "terminal.fill"
    )

    private static let dataRules: [AICodingPathRule] = [
        .init(
            "opencode.db*",
            category: .conversations,
            title: "OpenCode session database",
            explanation: "Saved OpenCode sessions and their SQLite database state."
        ),
        .init("opencode-*", category: .conversations),
        .init(
            "project",
            category: .conversations,
            title: "Legacy OpenCode projects",
            explanation: "Project and session data retained from earlier OpenCode versions."
        ),
        .init("storage", category: .conversations),
        .init(
            "snapshot",
            category: .recovery,
            title: "OpenCode snapshots",
            explanation: "Git snapshots used to recover changes made during coding tasks."
        ),
        .init(
            "plans",
            category: .artifacts,
            title: "OpenCode plans",
            explanation: "Plan documents saved outside a Git worktree."
        ),
        .init(
            "worktree",
            category: .worktrees,
            title: "OpenCode worktrees",
            explanation: "Isolated Git checkouts created for OpenCode tasks."
        ),
        .init(
            "repos",
            category: .worktrees,
            title: "OpenCode repository checkouts",
            explanation: "Local checkouts of remote repository references used by OpenCode."
        ),
        .init(
            "log",
            category: .logs,
            title: "OpenCode logs",
            explanation: "Diagnostic logs produced by OpenCode."
        ),
        .init(
            "auth.json",
            category: .configuration,
            title: "Provider credentials",
            explanation: "OpenCode provider credentials. SpaceLens measures file metadata only."
        )
    ]

    private static let configurationRules: [AICodingPathRule] = [
        .init("opencode.json", category: .configuration),
        .init("opencode.jsonc", category: .configuration),
        .init("config.json", category: .configuration),
        .init("tui.json", category: .configuration),
        .init("AGENTS.md", category: .configuration),
        .init("agents", category: .configuration),
        .init("agent", category: .configuration),
        .init("commands", category: .configuration),
        .init("command", category: .configuration),
        .init("modes", category: .configuration),
        .init("mode", category: .configuration),
        .init("skills", category: .configuration),
        .init("skill", category: .configuration),
        .init("tools", category: .configuration),
        .init("tool", category: .configuration),
        .init("themes", category: .configuration),
        .init("theme", category: .configuration),
        .init(
            "plugins",
            category: .extensions,
            title: "OpenCode plugins",
            explanation: "Installed OpenCode plugins and their supporting files."
        ),
        .init("plugin", category: .extensions),
        .init(
            "node_modules",
            category: .extensions,
            title: "OpenCode plugin dependencies",
            explanation: "Packages installed to support OpenCode plugins and configuration."
        ),
        .init("package.json", category: .extensions),
        .init("package-lock.json", category: .extensions),
        .init("pnpm-lock.yaml", category: .extensions),
        .init("yarn.lock", category: .extensions),
        .init("bun.lock", category: .extensions),
        .init("bun.lockb", category: .extensions)
    ]

    private static let projectRules: [AICodingPathRule] = [
        .init(
            "plans",
            category: .artifacts,
            title: "OpenCode project plans",
            explanation: "Plan documents created for this selected project."
        )
    ] + configurationRules

    private static let cacheRules: [AICodingPathRule] = [
        .init(
            "bin",
            category: .extensions,
            title: "OpenCode helper binaries",
            explanation: "Downloaded helper tools and language servers used by OpenCode."
        ),
        .init(
            "node_modules",
            category: .extensions,
            title: "OpenCode cached packages",
            explanation: "Downloaded packages used by OpenCode plugins and integrations."
        ),
        .init(
            "skills",
            category: .extensions,
            title: "Downloaded OpenCode skills",
            explanation: "Reusable skills downloaded for OpenCode."
        )
    ]

    private static let desktopRules: [AICodingPathRule] = [
        .init(
            "cli",
            category: .extensions,
            title: "OpenCode desktop CLI",
            explanation: "Command-line runtime bundled with the OpenCode desktop application."
        ),
        .init("opencode.settings*", category: .configuration),
        .init("opencode.global*", category: .configuration),
        .init("opencode.workspace*", category: .configuration),
        .init("opencode.window*", category: .configuration)
    ] + AICodingCatalogSupport.editorApplicationRules

    static func definition(for request: AICodingToolsRequest) -> AICodingToolDefinition {
        let home = request.homeDirectory.standardizedFileURL
        let appSupport = request.applicationSupportDirectory.standardizedFileURL
        var roots: [AICodingRootDescriptor] = []

        appendXDGRoots(
            to: &roots,
            directories: AICodingCatalogSupport.xdgApplicationDirectories(
                environmentKey: "XDG_DATA_HOME",
                defaultRelativeBase: ".local/share",
                applicationDirectory: "opencode",
                request: request
            ),
            name: "OpenCode data",
            customName: "OpenCode custom data",
            explanation: "OpenCode sessions, recovery snapshots, plans, worktrees, logs, and credentials.",
            customExplanation: "OpenCode data stored under XDG_DATA_HOME.",
            defaultCategory: .other,
            rules: dataRules,
            home: home
        )
        appendXDGRoots(
            to: &roots,
            directories: AICodingCatalogSupport.xdgApplicationDirectories(
                environmentKey: "XDG_CONFIG_HOME",
                defaultRelativeBase: ".config",
                applicationDirectory: "opencode",
                request: request
            ),
            name: "OpenCode configuration",
            customName: "OpenCode custom configuration",
            explanation: "OpenCode settings, rules, agents, plugins, skills, tools, and themes.",
            customExplanation: "OpenCode configuration stored under XDG_CONFIG_HOME.",
            defaultCategory: .configuration,
            rules: configurationRules,
            home: home
        )
        appendXDGRoots(
            to: &roots,
            directories: AICodingCatalogSupport.xdgApplicationDirectories(
                environmentKey: "XDG_CACHE_HOME",
                defaultRelativeBase: ".cache",
                applicationDirectory: "opencode",
                request: request
            ),
            name: "OpenCode cache",
            customName: "OpenCode custom cache",
            explanation: "Rebuildable OpenCode indexes, downloads, packages, and helper tools.",
            customExplanation: "OpenCode cache stored under XDG_CACHE_HOME.",
            defaultCategory: .caches,
            rules: cacheRules,
            home: home
        )
        appendXDGRoots(
            to: &roots,
            directories: AICodingCatalogSupport.xdgApplicationDirectories(
                environmentKey: "XDG_STATE_HOME",
                defaultRelativeBase: ".local/state",
                applicationDirectory: "opencode",
                request: request
            ),
            name: "OpenCode state",
            customName: "OpenCode custom state",
            explanation: "OpenCode command-line state and prompt history.",
            customExplanation: "OpenCode state stored under XDG_STATE_HOME.",
            defaultCategory: .other,
            rules: [
                .init(
                    "prompt-history.jsonl",
                    category: .conversations,
                    title: "OpenCode prompt history",
                    explanation: "Prompt history retained by the OpenCode terminal interface."
                )
            ],
            home: home
        )

        if let customConfiguration = AICodingCatalogSupport.absoluteConfiguredDirectory(
            environmentKey: "OPENCODE_CONFIG_DIR",
            request: request
        ) {
            roots.append(AICodingCatalogSupport.root(
                metadata.id,
                "OpenCode additional configuration",
                customConfiguration,
                "OpenCode configuration selected through OPENCODE_CONFIG_DIR.",
                defaultCategory: .configuration,
                rules: configurationRules,
                symlinkBoundaryURL: customConfiguration.deletingLastPathComponent()
            ))
        }

        roots.append(AICodingCatalogSupport.root(
            metadata.id,
            "OpenCode CLI installation",
            home.appendingPathComponent(".opencode", isDirectory: true),
            "OpenCode executable installed by the user-local installation script.",
            defaultCategory: .extensions,
            symlinkBoundaryURL: home
        ))

        for desktopDirectory in ["ai.opencode.desktop", "ai.opencode.desktop.beta"] {
            roots.append(AICodingCatalogSupport.root(
                metadata.id,
                desktopDirectory.hasSuffix(".beta")
                    ? "OpenCode Beta application data"
                    : "OpenCode application data",
                appSupport.appendingPathComponent(desktopDirectory, isDirectory: true),
                "OpenCode desktop interface state, caches, logs, and bundled runtime data.",
                rules: desktopRules,
                symlinkBoundaryURL: appSupport
            ))
        }

        let managedConfiguration = URL(
            fileURLWithPath: "/Library/Application Support/opencode",
            isDirectory: true
        )
        roots.append(AICodingCatalogSupport.root(
            metadata.id,
            "OpenCode managed configuration",
            managedConfiguration,
            "Administrator-managed OpenCode settings for this Mac.",
            defaultCategory: .configuration,
            rules: configurationRules,
            symlinkBoundaryURL: managedConfiguration.deletingLastPathComponent()
        ))

        roots.append(contentsOf: request.projectRoots.map { projectRoot in
            AICodingCatalogSupport.root(
                metadata.id,
                "OpenCode data in \(projectRoot.lastPathComponent)",
                projectRoot.appendingPathComponent(".opencode", isDirectory: true),
                "OpenCode agents, plugins, skills, tools, themes, and plans in a project root you selected.",
                defaultCategory: .configuration,
                rules: projectRules,
                symlinkBoundaryURL: projectRoot
            )
        })

        var seenPaths: Set<String> = []
        let uniqueRoots = roots.filter {
            seenPaths.insert($0.url.standardizedFileURL.path).inserted
        }
        return AICodingToolDefinition(metadata: metadata, roots: uniqueRoots)
    }

    private static func appendXDGRoots(
        to roots: inout [AICodingRootDescriptor],
        directories: [URL],
        name: String,
        customName: String,
        explanation: String,
        customExplanation: String,
        defaultCategory: AICodingStorageCategory,
        rules: [AICodingPathRule],
        home: URL
    ) {
        for (index, directory) in directories.enumerated() {
            roots.append(AICodingCatalogSupport.root(
                metadata.id,
                index == 0 ? name : customName,
                directory,
                index == 0 ? explanation : customExplanation,
                defaultCategory: defaultCategory,
                rules: rules,
                symlinkBoundaryURL: index == 0
                    ? home
                    : directory.deletingLastPathComponent().deletingLastPathComponent()
            ))
        }
    }
}
