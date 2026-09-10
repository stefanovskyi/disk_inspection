import Foundation

enum AICodingInstallationSurface: String, Equatable, Sendable {
    case nativeApplication
    case commandLine

    var displayName: String {
        switch self {
        case .nativeApplication: "Native app"
        case .commandLine: "CLI"
        }
    }

    var systemImage: String {
        switch self {
        case .nativeApplication: "macwindow"
        case .commandLine: "terminal"
        }
    }
}

enum AICodingInstallMethod: String, Equatable, Hashable, Sendable {
    case appStore
    case homebrewFormula
    case homebrewCask
    case npm
    case pnpm
    case yarn
    case bun
    case mise
    case nativeInstaller
    case directDownload

    var displayName: String {
        switch self {
        case .appStore: "Mac App Store"
        case .homebrewFormula: "Homebrew formula"
        case .homebrewCask: "Homebrew cask"
        case .npm: "npm"
        case .pnpm: "pnpm"
        case .yarn: "Yarn"
        case .bun: "Bun"
        case .mise: "Mise"
        case .nativeInstaller: "Native installer"
        case .directDownload: "Direct download"
        }
    }
}

enum AICodingInstallationConfidence: Int, Equatable, Comparable, Sendable {
    case heuristic
    case strong
    case authoritative

    static func < (
        lhs: AICodingInstallationConfidence,
        rhs: AICodingInstallationConfidence
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AICodingInstallationEvidenceKind: String, Equatable, Sendable {
    case appManifest
    case appStoreReceipt
    case homebrewReceipt
    case packageManifest
    case versionedRelease
    case commandLink
    case bundledComponent
    case fileMetadata

    var displayName: String {
        switch self {
        case .appManifest: "Application manifest"
        case .appStoreReceipt: "App Store receipt"
        case .homebrewReceipt: "Homebrew receipt"
        case .packageManifest: "Package manifest"
        case .versionedRelease: "Versioned release"
        case .commandLink: "Command link"
        case .bundledComponent: "Bundled component"
        case .fileMetadata: "Filesystem metadata"
        }
    }
}

struct AICodingInstallationEvidenceSource: Equatable, Sendable {
    let kind: AICodingInstallationEvidenceKind
    let url: URL
    let detail: String?

    init(
        _ kind: AICodingInstallationEvidenceKind,
        url: URL,
        detail: String? = nil
    ) {
        self.kind = kind
        self.url = url.standardizedFileURL
        self.detail = detail
    }
}

struct AICodingInstallationFact<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let source: AICodingInstallationEvidenceSource
    let confidence: AICodingInstallationConfidence
}

struct AICodingInstallationEntryPoint: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    let isOnProcessPath: Bool

    var id: String { url.standardizedFileURL.path }
}

struct AICodingInstallationComponent: Identifiable, Equatable, Sendable {
    let name: String
    let url: URL
    let version: AICodingInstallationFact<String>?

    var id: String { url.standardizedFileURL.path }
}

struct AICodingRetainedRelease: Identifiable, Equatable, Sendable {
    let version: String
    let url: URL
    let isActive: Bool

    var id: String { url.standardizedFileURL.path }
}

struct AICodingToolInstallation: Identifiable, Equatable, Sendable {
    let toolID: AICodingToolID
    let surface: AICodingInstallationSurface
    let displayName: String
    let rootURL: URL
    let entryPoints: [AICodingInstallationEntryPoint]
    let version: AICodingInstallationFact<String>?
    let build: AICodingInstallationFact<String>?
    let installMethod: AICodingInstallationFact<AICodingInstallMethod>?
    let installedOrUpdatedAt: AICodingInstallationFact<Date>?
    let observedFileDate: AICodingInstallationFact<Date>?
    let components: [AICodingInstallationComponent]
    let retainedReleases: [AICodingRetainedRelease]
    let notes: [String]

    var id: String {
        "\(toolID.rawValue)|\(surface.rawValue)|\(rootURL.standardizedFileURL.path)"
    }

    var isOnProcessPath: Bool { entryPoints.contains(where: \.isOnProcessPath) }

    init(
        toolID: AICodingToolID,
        surface: AICodingInstallationSurface,
        displayName: String,
        rootURL: URL,
        entryPoints: [AICodingInstallationEntryPoint] = [],
        version: AICodingInstallationFact<String>? = nil,
        build: AICodingInstallationFact<String>? = nil,
        installMethod: AICodingInstallationFact<AICodingInstallMethod>? = nil,
        installedOrUpdatedAt: AICodingInstallationFact<Date>? = nil,
        observedFileDate: AICodingInstallationFact<Date>? = nil,
        components: [AICodingInstallationComponent] = [],
        retainedReleases: [AICodingRetainedRelease] = [],
        notes: [String] = []
    ) {
        self.toolID = toolID
        self.surface = surface
        self.displayName = displayName
        self.rootURL = rootURL.standardizedFileURL
        self.entryPoints = Self.unique(entryPoints, by: { $0.id })
            .sorted { $0.url.path < $1.url.path }
        self.version = version
        self.build = build
        self.installMethod = installMethod
        self.installedOrUpdatedAt = installedOrUpdatedAt
        self.observedFileDate = observedFileDate
        self.components = Self.unique(components, by: { $0.id })
            .sorted { $0.name < $1.name }
        self.retainedReleases = Self.unique(retainedReleases, by: { $0.id })
            .sorted { left, right in
                if left.isActive != right.isActive { return left.isActive }
                return left.version.localizedStandardCompare(right.version) == .orderedDescending
            }
        self.notes = Array(Set(notes)).sorted()
    }

    private static func unique<Element>(
        _ values: [Element],
        by key: (Element) -> String
    ) -> [Element] {
        var seen: Set<String> = []
        return values.filter { seen.insert(key($0)).inserted }
    }
}
