import Foundation

enum CodexCatalog {
    static let metadata = AICodingToolMetadata(
        id: .codex,
        displayName: "Codex",
        systemImage: "chevron.left.forwardslash.chevron.right"
    )

    static func definition(for request: AICodingToolsRequest) -> AICodingToolDefinition {
        let rules: [AICodingPathRule] = [
            .init(
                "sessions",
                category: .conversations,
                title: "Codex sessions",
                explanation: "Saved Codex task sessions and their metadata."
            ),
            .init("archived_sessions", category: .conversations),
            .init("history.jsonl", category: .conversations),
            .init("thread_history.jsonl", category: .conversations),
            .init("session_index.jsonl", category: .conversations),
            .init(
                "worktrees",
                category: .worktrees,
                title: "Codex worktrees",
                explanation: "Isolated Git checkouts created for Codex tasks."
            ),
            .init(
                "generated_images",
                category: .artifacts,
                title: "Generated images",
                explanation: "Images generated during Codex tasks."
            ),
            .init("visualizations", category: .artifacts),
            .init("shell_snapshots", category: .recovery),
            .init(
                "plugins",
                category: .extensions,
                title: "Codex plugins",
                explanation: "Installed Codex plugin packages and resources."
            ),
            .init(
                "skills",
                category: .configuration,
                title: "Codex skills",
                explanation: "Reusable instructions and resources for Codex tasks."
            ),
            .init("memories", category: .configuration),
            .init("*.toml", category: .configuration),
            .init("config.json", category: .configuration),
            .init("logs", category: .logs),
            .init("log", category: .logs),
            .init("cache", category: .caches),
            .init("models_cache.json", category: .caches),
            .init("tmp", category: .caches)
        ]
        let home = request.homeDirectory
        let appSupport = request.applicationSupportDirectory
        let defaultHome = home.appendingPathComponent(".codex")
        var roots = [
            AICodingCatalogSupport.root(
                metadata.id,
                "Codex data",
                defaultHome,
                "Codex task history, worktrees, skills, plugins, logs, and generated outputs.",
                rules: rules,
                symlinkBoundaryURL: home
            )
        ]
        if let configuredHome = AICodingCatalogSupport.configuredDirectory(
            environmentKey: "CODEX_HOME",
            request: request
        ), configuredHome.standardizedFileURL.path != defaultHome.standardizedFileURL.path {
            roots.append(AICodingCatalogSupport.root(
                metadata.id,
                "Codex custom data",
                configuredHome,
                "Codex data selected through CODEX_HOME.",
                rules: rules,
                symlinkBoundaryURL: configuredHome.deletingLastPathComponent()
            ))
        }
        roots.append(AICodingCatalogSupport.root(
            metadata.id,
            "Codex application data",
            appSupport.appendingPathComponent("Codex"),
            "Codex desktop artifacts, browser state, caches, and logs.",
            rules: [
                .init("artifact-sessions", category: .artifacts),
                .init("Cache", category: .caches),
                .init("Code Cache", category: .caches),
                .init("GPUCache", category: .caches),
                .init("DawnCache", category: .caches),
                .init("DawnGraphiteCache", category: .caches),
                .init("Crashpad", category: .logs),
                .init("logs", category: .logs)
            ],
            symlinkBoundaryURL: appSupport
        ))
        return AICodingToolDefinition(metadata: metadata, roots: roots)
    }
}
