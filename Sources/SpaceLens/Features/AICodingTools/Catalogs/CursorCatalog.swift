import Foundation

enum CursorCatalog {
    static let metadata = AICodingToolMetadata(
        id: .cursor,
        displayName: "Cursor",
        systemImage: "cursorarrow.rays"
    )

    static func definition(for request: AICodingToolsRequest) -> AICodingToolDefinition {
        let rules: [AICodingPathRule] = [
            .init(
                "extensions",
                category: .extensions,
                title: "Cursor extensions",
                explanation: "Installed editor extensions and their bundled files."
            ),
            .init("plugins", category: .extensions),
            .init(
                "worktrees",
                category: .worktrees,
                title: "Cursor worktrees",
                explanation: "Isolated Git checkouts created for coding tasks."
            ),
            .init("plans", category: .artifacts),
            .init("snapshots", category: .recovery),
            .init(
                "projects",
                category: .conversations,
                title: "Cursor projects",
                explanation: "Project-specific agent sessions and state."
            ),
            .init(
                "debug-logs",
                category: .logs,
                title: "Cursor debug logs",
                explanation: "Diagnostic logs produced by Cursor agents."
            ),
            .init("skills", category: .configuration),
            .init("skills-cursor", category: .configuration)
        ]
        let home = request.homeDirectory
        let appSupport = request.applicationSupportDirectory
        return AICodingToolDefinition(metadata: metadata, roots: [
            AICodingCatalogSupport.root(
                metadata.id,
                "Cursor data",
                home.appendingPathComponent(".cursor"),
                "Cursor CLI, agent, extension, worktree, and project data.",
                rules: rules,
                symlinkBoundaryURL: home
            ),
            AICodingCatalogSupport.root(
                metadata.id,
                "Cursor application data",
                appSupport.appendingPathComponent("Cursor"),
                "Cursor editor state, recovery data, caches, and logs.",
                rules: AICodingCatalogSupport.editorApplicationRules,
                symlinkBoundaryURL: appSupport
            )
        ], installation: AICodingInstallationCatalogSupport.cursor(for: request))
    }
}
