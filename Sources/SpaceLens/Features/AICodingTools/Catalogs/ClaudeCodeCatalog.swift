import Foundation

enum ClaudeCodeCatalog {
    static let metadata = AICodingToolMetadata(
        id: .claudeCode,
        displayName: "Claude Code",
        systemImage: "terminal"
    )

    static func definition(for request: AICodingToolsRequest) -> AICodingToolDefinition {
        let rules: [AICodingPathRule] = [
            .init(
                "projects",
                category: .conversations,
                title: "Claude projects",
                explanation: "Project-specific Claude Code sessions and metadata."
            ),
            .init("projects/*/memory", category: .configuration),
            .init("history.jsonl", category: .conversations),
            .init("sessions", category: .conversations),
            .init("tasks", category: .conversations),
            .init("session-env", category: .conversations),
            .init("shell-snapshots", category: .recovery),
            .init(
                "file-history",
                category: .recovery,
                title: "Claude file history",
                explanation: "Snapshots used to recover files changed during coding sessions."
            ),
            .init("backups", category: .recovery),
            .init("plans", category: .artifacts),
            .init("paste-cache", category: .artifacts),
            .init("image-cache", category: .artifacts),
            .init("uploads", category: .artifacts),
            .init("feedback", category: .artifacts),
            .init("feedback-bundles", category: .artifacts),
            .init(
                "plugins",
                category: .extensions,
                title: "Claude plugins",
                explanation: "Installed Claude Code plugins and their dependencies."
            ),
            .init(
                "cache",
                category: .caches,
                title: "Claude cache",
                explanation: "Rebuildable data cached by Claude Code."
            ),
            .init("downloads", category: .caches),
            .init("debug", category: .logs),
            .init("logs", category: .logs),
            .init("telemetry", category: .logs),
            .init("settings.json", category: .configuration),
            .init("skills", category: .configuration),
            .init("rules", category: .configuration),
            .init("agents", category: .configuration),
            .init("commands", category: .configuration),
            .init("output-styles", category: .configuration),
            .init("agent-memory", category: .configuration)
        ]
        let home = request.homeDirectory
        let defaultHome = home.appendingPathComponent(".claude")
        var roots = [
            AICodingCatalogSupport.root(
                metadata.id,
                "Claude Code data",
                defaultHome,
                "Claude Code sessions, recovery history, plugins, settings, and generated data.",
                rules: rules,
                symlinkBoundaryURL: home
            )
        ]
        if let configuredHome = AICodingCatalogSupport.configuredDirectory(
            environmentKey: "CLAUDE_CONFIG_DIR",
            request: request
        ), configuredHome.standardizedFileURL.path != defaultHome.standardizedFileURL.path {
            roots.append(AICodingCatalogSupport.root(
                metadata.id,
                "Claude Code custom data",
                configuredHome,
                "Claude Code data selected through CLAUDE_CONFIG_DIR.",
                rules: rules,
                symlinkBoundaryURL: configuredHome.deletingLastPathComponent()
            ))
        }
        roots.append(AICodingCatalogSupport.root(
            metadata.id,
            "Claude Code runtimes",
            home.appendingPathComponent(".local/share/claude/versions"),
            "Downloaded Claude Code executable versions.",
            defaultCategory: .extensions,
            symlinkBoundaryURL: home
        ))
        roots.append(contentsOf: request.projectRoots.map { projectRoot in
            AICodingCatalogSupport.root(
                metadata.id,
                "Claude Code worktrees in \(projectRoot.lastPathComponent)",
                projectRoot.appendingPathComponent(".claude/worktrees"),
                "Claude Code worktrees discovered from a project root you selected.",
                defaultCategory: .worktrees,
                symlinkBoundaryURL: projectRoot
            )
        })
        return AICodingToolDefinition(
            metadata: metadata,
            roots: roots,
            installation: AICodingInstallationCatalogSupport.claudeCode(for: request)
        )
    }
}
