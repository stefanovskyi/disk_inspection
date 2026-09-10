import Foundation

struct AICodingApplicationInstallationRule: Equatable, Sendable {
    let displayName: String
    let bundleIdentifiers: [String]
    let fallbackBundleNames: [String]
    let bundledComponents: [AICodingBundledComponentRule]
}

struct AICodingBundledComponentRule: Equatable, Sendable {
    let name: String
    let relativePath: String
    let commandNames: [String]

    init(name: String, relativePath: String, commandNames: [String] = []) {
        self.name = name
        self.relativePath = relativePath
        self.commandNames = commandNames
    }
}

enum AICodingStandaloneVersionStrategy: Equatable, Sendable {
    case targetName
    case targetParentName
    case nearestVersionComponent
    case none
}

struct AICodingStandaloneInstallationRule: Equatable, Sendable {
    let displayName: String
    let owningRoot: URL?
    let entryPoints: [URL]
    let releasesDirectory: URL?
    let versionStrategy: AICodingStandaloneVersionStrategy
    let installMethod: AICodingInstallMethod
}

struct AICodingJavaScriptPackageRule: Equatable, Sendable {
    let packageName: String
    let displayName: String
    let commands: [String]
    let additionalNodeModulesRoots: [URL]
}

struct AICodingHomebrewRule: Equatable, Sendable {
    let token: String
    let displayName: String
    let surface: AICodingInstallationSurface
    let kind: AICodingInstallMethod
    let commands: [String]
}

struct AICodingInstallationDefinition: Equatable, Sendable {
    let toolID: AICodingToolID
    let applications: [AICodingApplicationInstallationRule]
    let standaloneCLIs: [AICodingStandaloneInstallationRule]
    let javaScriptPackages: [AICodingJavaScriptPackageRule]
    let homebrew: [AICodingHomebrewRule]
}

enum AICodingInstallationCatalogSupport {
    static func cursor(for request: AICodingToolsRequest) -> AICodingInstallationDefinition {
        let home = request.homeDirectory
        let releases = home.appendingPathComponent(".local/share/cursor-agent/versions")
        return AICodingInstallationDefinition(
            toolID: .cursor,
            applications: [
                AICodingApplicationInstallationRule(
                    displayName: "Cursor",
                    bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
                    fallbackBundleNames: ["Cursor.app"],
                    bundledComponents: [
                        AICodingBundledComponentRule(
                            name: "Cursor editor CLI",
                            relativePath: "Contents/Resources/app/bin/code",
                            commandNames: ["cursor"]
                        )
                    ]
                )
            ],
            standaloneCLIs: [
                AICodingStandaloneInstallationRule(
                    displayName: "Cursor Agent",
                    owningRoot: releases.deletingLastPathComponent(),
                    entryPoints: [
                        home.appendingPathComponent(".local/bin/agent"),
                        home.appendingPathComponent(".local/bin/cursor-agent")
                    ],
                    releasesDirectory: releases,
                    versionStrategy: .targetParentName,
                    installMethod: .nativeInstaller
                )
            ],
            javaScriptPackages: [],
            homebrew: [
                AICodingHomebrewRule(
                    token: "cursor",
                    displayName: "Cursor",
                    surface: .nativeApplication,
                    kind: .homebrewCask,
                    commands: ["cursor"]
                )
            ]
        )
    }

    static func claudeCode(for request: AICodingToolsRequest) -> AICodingInstallationDefinition {
        let home = request.homeDirectory
        let releases = home.appendingPathComponent(".local/share/claude/versions")
        return AICodingInstallationDefinition(
            toolID: .claudeCode,
            applications: [
                AICodingApplicationInstallationRule(
                    displayName: "Claude",
                    bundleIdentifiers: ["com.anthropic.claudefordesktop"],
                    fallbackBundleNames: ["Claude.app"],
                    bundledComponents: []
                )
            ],
            standaloneCLIs: [
                AICodingStandaloneInstallationRule(
                    displayName: "Claude Code",
                    owningRoot: releases.deletingLastPathComponent(),
                    entryPoints: [home.appendingPathComponent(".local/bin/claude")],
                    releasesDirectory: releases,
                    versionStrategy: .targetName,
                    installMethod: .nativeInstaller
                )
            ],
            javaScriptPackages: [
                AICodingJavaScriptPackageRule(
                    packageName: "@anthropic-ai/claude-code",
                    displayName: "Claude Code",
                    commands: ["claude"],
                    additionalNodeModulesRoots: [
                        home.appendingPathComponent(".claude/local/node_modules")
                    ]
                )
            ],
            homebrew: [
                AICodingHomebrewRule(
                    token: "claude-code",
                    displayName: "Claude Code",
                    surface: .commandLine,
                    kind: .homebrewCask,
                    commands: ["claude"]
                ),
                AICodingHomebrewRule(
                    token: "claude-code@latest",
                    displayName: "Claude Code",
                    surface: .commandLine,
                    kind: .homebrewCask,
                    commands: ["claude"]
                )
            ]
        )
    }

    static func codex(for request: AICodingToolsRequest) -> AICodingInstallationDefinition {
        let home = request.homeDirectory
        let codexHome = absoluteEnvironmentURL("CODEX_HOME", request: request)
            ?? home.appendingPathComponent(".codex")
        let packageRoot = codexHome.appendingPathComponent("packages/standalone")
        var entryPoints = [home.appendingPathComponent(".local/bin/codex")]
        if let installDirectory = absoluteEnvironmentURL("CODEX_INSTALL_DIR", request: request) {
            entryPoints.append(installDirectory.appendingPathComponent("codex"))
        }
        return AICodingInstallationDefinition(
            toolID: .codex,
            applications: [
                AICodingApplicationInstallationRule(
                    displayName: "ChatGPT with Codex",
                    bundleIdentifiers: ["com.openai.codex"],
                    fallbackBundleNames: ["ChatGPT.app", "Codex.app"],
                    bundledComponents: [
                        AICodingBundledComponentRule(
                            name: "Bundled Codex CLI",
                            relativePath: "Contents/Resources/codex",
                            commandNames: ["codex"]
                        )
                    ]
                )
            ],
            standaloneCLIs: [
                AICodingStandaloneInstallationRule(
                    displayName: "Codex CLI",
                    owningRoot: packageRoot,
                    entryPoints: entryPoints,
                    releasesDirectory: packageRoot.appendingPathComponent("releases"),
                    versionStrategy: .nearestVersionComponent,
                    installMethod: .nativeInstaller
                )
            ],
            javaScriptPackages: [
                AICodingJavaScriptPackageRule(
                    packageName: "@openai/codex",
                    displayName: "Codex CLI",
                    commands: ["codex"],
                    additionalNodeModulesRoots: []
                )
            ],
            homebrew: [
                AICodingHomebrewRule(
                    token: "codex",
                    displayName: "Codex CLI",
                    surface: .commandLine,
                    kind: .homebrewCask,
                    commands: ["codex"]
                )
            ]
        )
    }

    static func antigravity(for request: AICodingToolsRequest) -> AICodingInstallationDefinition {
        let home = request.homeDirectory
        return AICodingInstallationDefinition(
            toolID: .antigravity,
            applications: [
                AICodingApplicationInstallationRule(
                    displayName: "Antigravity",
                    bundleIdentifiers: ["com.google.antigravity"],
                    fallbackBundleNames: ["Antigravity.app"],
                    bundledComponents: []
                ),
                AICodingApplicationInstallationRule(
                    displayName: "Antigravity IDE",
                    bundleIdentifiers: ["com.google.antigravity-ide"],
                    fallbackBundleNames: ["Antigravity IDE.app"],
                    bundledComponents: []
                )
            ],
            standaloneCLIs: [
                AICodingStandaloneInstallationRule(
                    displayName: "Antigravity CLI",
                    owningRoot: nil,
                    entryPoints: [home.appendingPathComponent(".local/bin/agy")],
                    releasesDirectory: nil,
                    versionStrategy: .none,
                    installMethod: .nativeInstaller
                )
            ],
            javaScriptPackages: [],
            homebrew: []
        )
    }

    static func openCode(for request: AICodingToolsRequest) -> AICodingInstallationDefinition {
        let home = request.homeDirectory
        var entryPoints = [
            home.appendingPathComponent(".opencode/bin/opencode"),
            home.appendingPathComponent(".local/bin/opencode"),
            home.appendingPathComponent("bin/opencode")
        ]
        if let configured = absoluteEnvironmentURL("OPENCODE_INSTALL_DIR", request: request) {
            entryPoints.append(configured.appendingPathComponent("opencode"))
        }
        if let configured = absoluteEnvironmentURL("XDG_BIN_DIR", request: request) {
            entryPoints.append(configured.appendingPathComponent("opencode"))
        }
        return AICodingInstallationDefinition(
            toolID: .openCode,
            applications: [
                AICodingApplicationInstallationRule(
                    displayName: "OpenCode",
                    bundleIdentifiers: ["ai.opencode.desktop", "ai.opencode.desktop.beta"],
                    fallbackBundleNames: ["OpenCode.app", "OpenCode Desktop.app"],
                    bundledComponents: []
                )
            ],
            standaloneCLIs: [
                AICodingStandaloneInstallationRule(
                    displayName: "OpenCode CLI",
                    owningRoot: nil,
                    entryPoints: entryPoints,
                    releasesDirectory: nil,
                    versionStrategy: .none,
                    installMethod: .directDownload
                )
            ],
            javaScriptPackages: [
                AICodingJavaScriptPackageRule(
                    packageName: "opencode-ai",
                    displayName: "OpenCode CLI",
                    commands: ["opencode"],
                    additionalNodeModulesRoots: []
                )
            ],
            homebrew: [
                AICodingHomebrewRule(
                    token: "opencode",
                    displayName: "OpenCode CLI",
                    surface: .commandLine,
                    kind: .homebrewFormula,
                    commands: ["opencode"]
                ),
                AICodingHomebrewRule(
                    token: "opencode-desktop",
                    displayName: "OpenCode",
                    surface: .nativeApplication,
                    kind: .homebrewCask,
                    commands: []
                )
            ]
        )
    }

    private static func absoluteEnvironmentURL(
        _ key: String,
        request: AICodingToolsRequest
    ) -> URL? {
        guard let value = request.environment[key], value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }
}
