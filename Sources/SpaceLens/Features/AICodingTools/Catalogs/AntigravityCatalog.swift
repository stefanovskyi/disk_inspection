import Foundation

enum AntigravityCatalog {
    static let metadata = AICodingToolMetadata(
        id: .antigravity,
        displayName: "Google Antigravity",
        systemImage: "sparkles"
    )

    static func definition(for request: AICodingToolsRequest) -> AICodingToolDefinition {
        let home = request.homeDirectory
        let appSupport = request.applicationSupportDirectory
        return AICodingToolDefinition(metadata: metadata, roots: [
            AICodingCatalogSupport.root(
                metadata.id,
                "Antigravity data",
                home.appendingPathComponent(".gemini/antigravity"),
                "Antigravity sessions, generated artifacts, knowledge, and runtime state.",
                rules: [
                    .init(
                        "conversations",
                        category: .conversations,
                        title: "Antigravity conversations",
                        explanation: "Saved Antigravity conversations and session state."
                    ),
                    .init("sessions", category: .conversations),
                    .init(
                        "brain",
                        category: .artifacts,
                        title: "Antigravity task artifacts",
                        explanation: "Generated task plans, outputs, and supporting files."
                    ),
                    .init("brain/*/.system_generated/logs", category: .conversations),
                    .init(
                        "browser_recordings",
                        category: .artifacts,
                        title: "Browser recordings",
                        explanation: "Browser recordings captured during coding tasks."
                    ),
                    .init("html_artifacts", category: .artifacts),
                    .init("playground", category: .artifacts),
                    .init("bin", category: .extensions),
                    .init("builtin", category: .extensions),
                    .init("cache", category: .caches),
                    .init("crashes", category: .logs),
                    .init("logs", category: .logs),
                    .init("knowledge", category: .configuration),
                    .init("prompting", category: .configuration),
                    .init("settings.json", category: .configuration)
                ],
                symlinkBoundaryURL: home
            ),
            AICodingCatalogSupport.root(
                metadata.id,
                "Antigravity CLI data",
                home.appendingPathComponent(".gemini/antigravity-cli"),
                "Antigravity CLI sessions, artifacts, caches, and settings.",
                rules: [
                    .init("conversations", category: .conversations),
                    .init("sessions", category: .conversations),
                    .init("artifacts", category: .artifacts),
                    .init("cache", category: .caches),
                    .init("logs", category: .logs),
                    .init("settings.json", category: .configuration),
                    .init("config.json", category: .configuration)
                ],
                symlinkBoundaryURL: home
            ),
            AICodingCatalogSupport.root(
                metadata.id,
                "Antigravity IDE data",
                home.appendingPathComponent(".antigravity"),
                "Antigravity IDE extensions, state, and settings.",
                rules: [
                    .init("extensions", category: .extensions),
                    .init("cache", category: .caches),
                    .init("logs", category: .logs),
                    .init("settings.json", category: .configuration),
                    .init("config.json", category: .configuration)
                ],
                symlinkBoundaryURL: home
            ),
            AICodingCatalogSupport.root(
                metadata.id,
                "Antigravity extensions",
                home.appendingPathComponent(".antigravity-server/extensions"),
                "Installed Antigravity server extensions.",
                defaultCategory: .extensions,
                symlinkBoundaryURL: home
            ),
            AICodingCatalogSupport.root(
                metadata.id,
                "Antigravity application data",
                appSupport.appendingPathComponent("Antigravity"),
                "Antigravity editor state, recovery data, caches, and logs.",
                rules: AICodingCatalogSupport.editorApplicationRules,
                symlinkBoundaryURL: appSupport
            )
        ])
    }
}
