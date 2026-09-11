import Foundation

struct DeveloperStorageRequest: Sendable {
    let homeDirectory: URL
    let environment: [String: String]
    let automaticProjectContainers: [URL]
    let projectContainers: [URL]
    let systemJDKDirectories: [URL]
    let homebrewPrefixes: [URL]

    init(
        homeDirectory: URL,
        environment: [String: String],
        automaticProjectContainers: [URL] = [],
        projectContainers: [URL],
        systemJDKDirectories: [URL] = [],
        homebrewPrefixes: [URL] = []
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.environment = environment
        self.automaticProjectContainers = automaticProjectContainers.map(\.standardizedFileURL)
        self.projectContainers = projectContainers.map(\.standardizedFileURL)
        self.systemJDKDirectories = systemJDKDirectories.map(\.standardizedFileURL)
        self.homebrewPrefixes = homebrewPrefixes.map(\.standardizedFileURL)
    }

    static func currentUser(projectContainers: [URL] = []) -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        return Self(
            homeDirectory: home,
            environment: ProcessInfo.processInfo.environment,
            automaticProjectContainers: [home],
            projectContainers: projectContainers,
            systemJDKDirectories: [
                home.appendingPathComponent("Library/Java/JavaVirtualMachines", isDirectory: true),
                URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines", isDirectory: true)
            ],
            homebrewPrefixes: [
                URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
                URL(fileURLWithPath: "/usr/local", isDirectory: true)
            ]
        )
    }
}

struct DeveloperArtifactRule: Equatable, Sendable {
    let components: [String]
    let kind: DeveloperArtifactKind

    init(_ relativePath: String, kind: DeveloperArtifactKind) {
        components = relativePath.split(separator: "/").map(String.init)
        self.kind = kind
    }

    func matches(_ candidate: [String]) -> Bool {
        candidate.count >= components.count
            && Array(candidate.prefix(components.count)) == components
    }
}

struct DeveloperArtifactDescriptor: Equatable, Sendable {
    let ecosystemID: DeveloperEcosystemID
    let scope: DeveloperStorageScope
    let kind: DeveloperArtifactKind
    let name: String
    let url: URL
    let projectURL: URL?
    let rules: [DeveloperArtifactRule]
    let symlinkBoundaryURL: URL?

    init(
        ecosystemID: DeveloperEcosystemID,
        scope: DeveloperStorageScope,
        kind: DeveloperArtifactKind,
        name: String,
        url: URL,
        projectURL: URL? = nil,
        rules: [DeveloperArtifactRule] = [],
        symlinkBoundaryURL: URL? = nil
    ) {
        self.ecosystemID = ecosystemID
        self.scope = scope
        self.kind = kind
        self.name = name
        self.url = url.standardizedFileURL
        self.projectURL = projectURL?.standardizedFileURL
        self.rules = rules
        self.symlinkBoundaryURL = symlinkBoundaryURL?.standardizedFileURL
    }

    var id: String {
        "\(ecosystemID.rawValue)|\(scope.rawValue)|\(url.standardizedFileURL.path)"
    }

    func category(for itemURL: URL) -> DeveloperArtifactKind {
        let rootComponents = url.standardizedFileURL.pathComponents
        let itemComponents = itemURL.standardizedFileURL.pathComponents
        guard itemComponents.count >= rootComponents.count else { return kind }
        let relative = Array(itemComponents.dropFirst(rootComponents.count))
        return rules.enumerated()
            .filter { $0.element.matches(relative) }
            .sorted {
                if $0.element.components.count == $1.element.components.count {
                    return $0.offset < $1.offset
                }
                return $0.element.components.count > $1.element.components.count
            }
            .first?.element.kind ?? kind
    }
}

protocol DeveloperStorageAnalyzing: Sendable {
    func analyze(
        request: DeveloperStorageRequest,
        onProgress: @escaping @Sendable (DeveloperStorageProgress) -> Void
    ) async throws -> DeveloperStorageReport
}
