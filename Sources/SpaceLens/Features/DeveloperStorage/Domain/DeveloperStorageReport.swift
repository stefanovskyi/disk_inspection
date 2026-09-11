import Foundation

enum DeveloperEcosystemID: String, CaseIterable, Identifiable, Sendable {
    case nodeAndWeb
    case python
    case javaAndJVM

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nodeAndWeb: "Node.js & Web"
        case .python: "Python"
        case .javaAndJVM: "Java & JVM"
        }
    }

    var systemImage: String {
        switch self {
        case .nodeAndWeb: "shippingbox.fill"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .javaAndJVM: "cup.and.saucer.fill"
        }
    }
}

enum DeveloperStorageScope: String, CaseIterable, Identifiable, Sendable {
    case project
    case shared

    var id: String { rawValue }
    var displayName: String { self == .project ? "Projects" : "Shared" }
}

enum DeveloperArtifactKind: String, CaseIterable, Identifiable, Sendable {
    case projectDependencies
    case environments
    case buildOutputs
    case projectCaches
    case sharedCaches
    case toolchains
    case toolState
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .projectDependencies: "Project dependencies"
        case .environments: "Environments"
        case .buildOutputs: "Build outputs"
        case .projectCaches: "Project caches"
        case .sharedCaches: "Shared caches & stores"
        case .toolchains: "Toolchains & runtimes"
        case .toolState: "Tool state & diagnostics"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .projectDependencies: "shippingbox"
        case .environments: "terminal"
        case .buildOutputs: "hammer"
        case .projectCaches: "bolt.horizontal.circle"
        case .sharedCaches: "internaldrive"
        case .toolchains: "wrench.and.screwdriver"
        case .toolState: "waveform.path.ecg"
        case .other: "tray.full"
        }
    }
}

struct DeveloperStorageBreakdown: Identifiable, Equatable, Sendable {
    let kind: DeveloperArtifactKind
    let uniqueSize: Int64
    let referencedSize: Int64
    let itemCount: Int

    var id: String { kind.id }
}

enum DeveloperStorageLocationStatus: String, Equatable, Sendable {
    case measured
    case unreadable
    case stalled
    case linked

    var displayName: String {
        switch self {
        case .measured: "Measured"
        case .unreadable: "Partly unreadable"
        case .stalled: "Scan timed out"
        case .linked: "Linked location skipped"
        }
    }

    var isIssue: Bool { self != .measured }
}

struct DeveloperStorageLocation: Identifiable, Equatable, Sendable {
    let ecosystemID: DeveloperEcosystemID
    let scope: DeveloperStorageScope
    let kind: DeveloperArtifactKind
    let name: String
    let url: URL
    let projectURL: URL?
    let uniqueSize: Int64
    let referencedSize: Int64
    let itemCount: Int
    let latestModificationDate: Date?
    let status: DeveloperStorageLocationStatus
    let root: FileNode?
    let breakdowns: [DeveloperStorageBreakdown]

    var id: String {
        "\(ecosystemID.rawValue)|\(scope.rawValue)|\(url.standardizedFileURL.path)"
    }

    var hasSharedBytes: Bool { referencedSize > uniqueSize }
}

struct DeveloperProjectReport: Identifiable, Equatable, Sendable {
    let url: URL
    let locations: [DeveloperStorageLocation]

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    var artifactCount: Int { locations.count }
    var itemCount: Int { locations.reduce(0) { developerSafeAdd($0, $1.itemCount) } }
    var issueCount: Int { locations.filter { $0.status.isIssue }.count }
    var uniqueSize: Int64 { locations.reduce(0) { developerSafeAdd($0, $1.uniqueSize) } }
    var referencedSize: Int64 { locations.reduce(0) { developerSafeAdd($0, $1.referencedSize) } }
}

struct DeveloperEcosystemReport: Identifiable, Equatable, Sendable {
    let ecosystemID: DeveloperEcosystemID
    let locations: [DeveloperStorageLocation]

    var id: DeveloperEcosystemID { ecosystemID }
    var displayName: String { ecosystemID.displayName }
    var systemImage: String { ecosystemID.systemImage }
    var uniqueSize: Int64 { locations.reduce(0) { developerSafeAdd($0, $1.uniqueSize) } }
    var referencedSize: Int64 { locations.reduce(0) { developerSafeAdd($0, $1.referencedSize) } }
    var itemCount: Int { locations.reduce(0) { developerSafeAdd($0, $1.itemCount) } }
    var issueCount: Int { locations.filter { $0.status.isIssue }.count }
    var projectSize: Int64 {
        locations.filter { $0.scope == .project }.reduce(0) { developerSafeAdd($0, $1.uniqueSize) }
    }
    var sharedSize: Int64 {
        locations.filter { $0.scope == .shared }.reduce(0) { developerSafeAdd($0, $1.uniqueSize) }
    }
    var projects: [DeveloperProjectReport] {
        Dictionary(grouping: locations.filter { $0.scope == .project }) {
            $0.projectURL ?? $0.url.deletingLastPathComponent()
        }
        .map { DeveloperProjectReport(url: $0.key, locations: $0.value.sorted(by: locationOrder)) }
        .sorted { $0.uniqueSize == $1.uniqueSize ? $0.name < $1.name : $0.uniqueSize > $1.uniqueSize }
    }
    var sharedLocations: [DeveloperStorageLocation] {
        locations.filter { $0.scope == .shared }.sorted(by: locationOrder)
    }
    var breakdowns: [DeveloperStorageBreakdown] {
        DeveloperArtifactKind.allCases.compactMap { kind in
            let matching = locations.flatMap(\.breakdowns).filter { $0.kind == kind }
            guard !matching.isEmpty else { return nil }
            return DeveloperStorageBreakdown(
                kind: kind,
                uniqueSize: matching.reduce(0) { developerSafeAdd($0, $1.uniqueSize) },
                referencedSize: matching.reduce(0) { developerSafeAdd($0, $1.referencedSize) },
                itemCount: matching.reduce(0) { developerSafeAdd($0, $1.itemCount) }
            )
        }
        .sorted { $0.uniqueSize == $1.uniqueSize ? $0.kind.rawValue < $1.kind.rawValue : $0.uniqueSize > $1.uniqueSize }
    }

    private func locationOrder(_ left: DeveloperStorageLocation, _ right: DeveloperStorageLocation) -> Bool {
        left.uniqueSize == right.uniqueSize ? left.name < right.name : left.uniqueSize > right.uniqueSize
    }
}

struct DeveloperStorageReport: Equatable, Sendable {
    let ecosystems: [DeveloperEcosystemReport]
    let startedAt: Date
    let completedAt: Date
    let duration: TimeInterval
    let discoveryIssueCount: Int

    init(
        ecosystems: [DeveloperEcosystemReport],
        startedAt: Date,
        completedAt: Date = Date(),
        discoveryIssueCount: Int = 0
    ) {
        self.ecosystems = ecosystems
        self.startedAt = startedAt
        self.completedAt = completedAt
        duration = max(completedAt.timeIntervalSince(startedAt), 0)
        self.discoveryIssueCount = discoveryIssueCount
    }

    var rankedEcosystems: [DeveloperEcosystemReport] {
        ecosystems.sorted {
            $0.uniqueSize == $1.uniqueSize ? $0.displayName < $1.displayName : $0.uniqueSize > $1.uniqueSize
        }
    }
    var totalSize: Int64 { ecosystems.reduce(0) { developerSafeAdd($0, $1.uniqueSize) } }
    var referencedSize: Int64 { ecosystems.reduce(0) { developerSafeAdd($0, $1.referencedSize) } }
    var itemCount: Int { ecosystems.reduce(0) { developerSafeAdd($0, $1.itemCount) } }
    var locationCount: Int { ecosystems.reduce(0) { developerSafeAdd($0, $1.locations.count) } }
    var issueCount: Int {
        ecosystems.reduce(discoveryIssueCount) { developerSafeAdd($0, $1.issueCount) }
    }
}

struct DeveloperStorageProgress: Equatable, Sendable {
    var currentEcosystem: DeveloperEcosystemID?
    var currentLocationName: String?
    var currentPath: String?
    var discoveredArtifacts = 0
    var completedLocations = 0
    var totalLocations = 0
    var itemsScanned = 0
    var mappedBytes: Int64 = 0

    var fractionCompleted: Double? {
        guard totalLocations > 0 else { return nil }
        return min(max(Double(completedLocations) / Double(totalLocations), 0), 1)
    }
}

enum DeveloperStorageAnalysisState: Equatable, Sendable {
    case idle
    case running(previousReport: DeveloperStorageReport?)
    case completed(DeveloperStorageReport)
    case failed(message: String, previousReport: DeveloperStorageReport?)

    var report: DeveloperStorageReport? {
        switch self {
        case .idle: nil
        case .running(let report): report
        case .completed(let report): report
        case .failed(_, let report): report
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

private func developerSafeAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int64.max : result.partialValue
}

private func developerSafeAdd(_ left: Int, _ right: Int) -> Int {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int.max : result.partialValue
}
