import Foundation

enum T3CodeCatalog {
    static let metadata = AICodingToolMetadata(
        id: .t3Code,
        displayName: "T3 Code",
        systemImage: "rectangle.3.group.bubble"
    )

    private static let stateRules: [AICodingPathRule] = [
        .init(
            "statev2.sqlite*",
            category: .conversations,
            title: "T3 Code thread database",
            explanation: "Projects, threads, messages, and orchestration history in T3 Code's SQLite database."
        ),
        .init(
            "attachments",
            category: .artifacts,
            title: "Thread attachments",
            explanation: "Files and images attached to T3 Code threads."
        ),
        .init(
            "browser-artifacts",
            category: .artifacts,
            title: "Browser artifacts",
            explanation: "Files captured by T3 Code's in-app browser during coding tasks."
        ),
        .init(
            "logs",
            category: .logs,
            title: "T3 Code logs",
            explanation: "Server traces, provider event logs, and terminal logs."
        ),
        .init(
            "usage-*",
            category: .caches,
            title: "Usage cache",
            explanation: "Rebuildable usage totals and model rate data."
        ),
        .init(
            "model-manifest.json",
            category: .caches,
            title: "Model manifest",
            explanation: "Cached copy of the model catalog downloaded by T3 Code."
        ),
        .init(
            "secrets",
            category: .configuration,
            title: "T3 Code secrets",
            explanation: "Signing keys used by T3 Code. SpaceLens measures file metadata only."
        ),
        .init(
            "clerk",
            category: .configuration,
            title: "Account credentials",
            explanation: "T3 Code sign-in tokens. SpaceLens measures file metadata only."
        ),
        .init("settings.json", category: .configuration),
        .init("client-settings.json", category: .configuration),
        .init("desktop-settings.json", category: .configuration),
        .init("saved-environments.json", category: .configuration),
        .init("keybindings.json", category: .configuration),
        .init("keybindings-migrations", category: .configuration),
        .init("themes", category: .configuration),
        .init("anonymous-id", category: .configuration),
        .init("environment-id", category: .configuration)
    ]

    private static let homeRules: [AICodingPathRule] = [
        .init(
            "worktrees",
            category: .worktrees,
            title: "T3 Code worktrees",
            explanation: "Isolated Git checkouts created for T3 Code threads."
        ),
        .init(
            "caches",
            category: .caches,
            title: "Provider status cache",
            explanation: "Rebuildable agent provider status and registry data."
        ),
        .init(
            "runtime",
            category: .extensions,
            title: "T3 CLI runtime",
            explanation: "Versions of the self-contained t3 command-line runtime."
        ),
        .init(
            "bin",
            category: .extensions,
            title: "T3 command launcher",
            explanation: "Launcher that runs the t3 command bundled with the desktop application."
        ),
        .init("usage-host-id", category: .configuration)
    ]
    + stateRules.map { $0.prefixing(["userdata"]) }
    + stateRules.map { $0.prefixing(["dev"]) }

    private static let applicationRules: [AICodingPathRule] = [
        .init(
            "Cache",
            category: .caches,
            title: "Application cache",
            explanation: "Rebuildable application cache data."
        ),
        .init("Code Cache", category: .caches),
        .init("GPUCache", category: .caches),
        .init("GPUPersistentCache", category: .caches),
        .init("DawnGraphiteCache", category: .caches),
        .init("DawnWebGPUCache", category: .caches),
        .init("GraphiteDawnCache", category: .caches),
        .init("Shared Dictionary", category: .caches),
        .init("Crashpad", category: .logs),
        .init("logs", category: .logs)
    ]

    private static let earlierApplicationDirectories = [
        (directory: "t3code", name: "T3 Code earlier application data"),
        (directory: "T3 Code (Alpha)", name: "T3 Code Alpha application data"),
        (directory: "t3code-dev", name: "T3 Code development application data"),
        (directory: "T3 Code (Dev)", name: "T3 Code earlier development application data")
    ]

    static func definition(for request: AICodingToolsRequest) -> AICodingToolDefinition {
        let home = request.homeDirectory
        let appSupport = request.applicationSupportDirectory
        let defaultHome = home.appendingPathComponent(".t3", isDirectory: true)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        var roots = [
            AICodingCatalogSupport.root(
                metadata.id,
                "T3 Code data",
                defaultHome,
                "T3 Code threads, worktrees, attachments, logs, settings, and caches.",
                rules: homeRules,
                symlinkBoundaryURL: home
            )
        ]
        if let configuredHome = AICodingCatalogSupport.absoluteConfiguredDirectory(
            environmentKey: "T3CODE_HOME",
            request: request
        ), configuredHome.path != defaultHome.standardizedFileURL.path {
            roots.append(AICodingCatalogSupport.root(
                metadata.id,
                "T3 Code custom data",
                configuredHome,
                "T3 Code data selected through T3CODE_HOME.",
                rules: homeRules,
                symlinkBoundaryURL: configuredHome.deletingLastPathComponent()
            ))
        }
        roots.append(AICodingCatalogSupport.root(
            metadata.id,
            "T3 Code application data",
            appSupport.appendingPathComponent("t3code-v2", isDirectory: true),
            "T3 Code desktop interface state, browser storage, and rebuildable render caches.",
            rules: applicationRules,
            symlinkBoundaryURL: appSupport
        ))
        roots.append(contentsOf: earlierApplicationDirectories.map { entry in
            AICodingCatalogSupport.root(
                metadata.id,
                entry.name,
                appSupport.appendingPathComponent(entry.directory, isDirectory: true),
                "Desktop interface state kept by another T3 Code release or build.",
                rules: applicationRules,
                symlinkBoundaryURL: appSupport,
                reportsWhenMissing: false
            )
        })
        roots.append(AICodingCatalogSupport.root(
            metadata.id,
            "T3 Code cache",
            caches.appendingPathComponent("com.t3tools.t3code", isDirectory: true),
            "Rebuildable data cached by the T3 Code desktop application.",
            defaultCategory: .caches,
            symlinkBoundaryURL: home,
            reportsWhenMissing: false
        ))
        roots.append(AICodingCatalogSupport.root(
            metadata.id,
            "T3 Code update downloads",
            caches.appendingPathComponent("t3code-updater", isDirectory: true),
            "Application updates downloaded by T3 Code's automatic updater.",
            defaultCategory: .caches,
            symlinkBoundaryURL: home,
            reportsWhenMissing: false
        ))
        return AICodingToolDefinition(
            metadata: metadata,
            roots: roots,
            installation: AICodingInstallationCatalogSupport.t3Code(for: request)
        )
    }
}
