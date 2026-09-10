import Foundation

struct AICodingToolID: Hashable, Identifiable, RawRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }

    static let cursor = Self(rawValue: "cursor")
    static let claudeCode = Self(rawValue: "claude-code")
    static let codex = Self(rawValue: "codex")
    static let antigravity = Self(rawValue: "antigravity")
    static let openCode = Self(rawValue: "opencode")
}

struct AICodingToolMetadata: Identifiable, Equatable, Sendable {
    let id: AICodingToolID
    let displayName: String
    let systemImage: String

    static func fallback(for id: AICodingToolID) -> Self {
        Self(id: id, displayName: id.rawValue, systemImage: "hammer")
    }
}

enum AICodingStorageCategory: String, CaseIterable, Identifiable, Sendable {
    case conversations
    case recovery
    case artifacts
    case worktrees
    case extensions
    case caches
    case logs
    case configuration
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .conversations: "Conversations & sessions"
        case .recovery: "Recovery & history"
        case .artifacts: "Generated artifacts"
        case .worktrees: "Worktrees & checkouts"
        case .extensions: "Extensions & runtimes"
        case .caches: "Caches & indexes"
        case .logs: "Logs & diagnostics"
        case .configuration: "Configuration & memory"
        case .other: "Other tool data"
        }
    }

    var systemImage: String {
        switch self {
        case .conversations: "bubble.left.and.bubble.right"
        case .recovery: "clock.arrow.circlepath"
        case .artifacts: "wand.and.stars"
        case .worktrees: "arrow.triangle.branch"
        case .extensions: "puzzlepiece.extension"
        case .caches: "bolt.horizontal.circle"
        case .logs: "doc.text.magnifyingglass"
        case .configuration: "gearshape"
        case .other: "tray.full"
        }
    }

    var explanation: String {
        switch self {
        case .conversations: "Local conversation records and active session state."
        case .recovery: "File history, backups, and recovery snapshots."
        case .artifacts: "Plans, images, recordings, and other generated outputs."
        case .worktrees: "Extra Git checkouts created for isolated coding tasks."
        case .extensions: "Installed extensions, plugins, and bundled runtimes."
        case .caches: "Rebuildable caches, indexes, and downloaded metadata."
        case .logs: "Logs, crash reports, and diagnostic traces."
        case .configuration: "Settings, skills, rules, and durable project memory."
        case .other: "Tool-owned data whose purpose cannot be classified safely from its path."
        }
    }
}

enum AICodingLocationStatus: String, Sendable {
    case measured
    case missing
    case unreadable
    case stalled
    case linked
    case notDiscoverable

    var displayName: String {
        switch self {
        case .measured: "Measured"
        case .missing: "Not found"
        case .unreadable: "Partly unreadable"
        case .stalled: "Scan timed out"
        case .linked: "Linked location skipped"
        case .notDiscoverable: "Not automatically discoverable"
        }
    }

    var isIssue: Bool { self != .measured && self != .missing }
}

struct AICodingCategoryBreakdown: Identifiable, Equatable, Sendable {
    let category: AICodingStorageCategory
    let size: Int64
    let itemCount: Int
    let latestModificationDate: Date?

    var id: String { category.id }
}

struct AICodingPathRule: Equatable, Sendable {
    let components: [String]
    let category: AICodingStorageCategory
    let title: String
    let explanation: String

    init(
        _ path: String,
        category: AICodingStorageCategory,
        title: String? = nil,
        explanation: String? = nil
    ) {
        components = path.split(separator: "/").map(String.init)
        self.category = category
        self.title = title ?? category.displayName
        self.explanation = explanation ?? category.explanation
    }

    func matches(_ pathComponents: [String]) -> Bool {
        guard pathComponents.count >= components.count else { return false }
        return zip(components, pathComponents).allSatisfy { pattern, component in
            if pattern == "*" { return true }
            if pattern.hasPrefix("*.") {
                return component.hasSuffix(String(pattern.dropFirst()))
            }
            if pattern.hasSuffix("*") {
                return component.hasPrefix(String(pattern.dropLast()))
            }
            return pattern == component
        }
    }

    func prefixing(_ prefix: [String]) -> Self {
        Self(
            (prefix + components).joined(separator: "/"),
            category: category,
            title: title,
            explanation: explanation
        )
    }
}

struct AICodingNodeAnnotation: Equatable, Sendable {
    let category: AICodingStorageCategory
    let title: String
    let explanation: String
    let isComponentRoot: Bool
}

struct AICodingStorageLocation: Identifiable, Equatable, Sendable {
    let toolID: AICodingToolID
    let name: String
    let url: URL
    let explanation: String
    let status: AICodingLocationStatus
    let root: FileNode?
    let categories: [AICodingCategoryBreakdown]
    let defaultCategory: AICodingStorageCategory
    let rules: [AICodingPathRule]

    var id: String { url.standardizedFileURL.path }

    var size: Int64 {
        root?.size ?? categories.reduce(0) { partial, category in
            let result = partial.addingReportingOverflow(category.size)
            return result.overflow ? Int64.max : result.partialValue
        }
    }

    var itemCount: Int {
        root?.itemCount ?? categories.reduce(0) { partial, category in
            let result = partial.addingReportingOverflow(category.itemCount)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    var latestModificationDate: Date? {
        categories.compactMap(\.latestModificationDate).max()
    }

    func breakdown(for category: AICodingStorageCategory) -> AICodingCategoryBreakdown? {
        categories.first { $0.category == category }
    }

    func annotation(for node: FileNode) -> AICodingNodeAnnotation {
        if node.isAggregate {
            return AICodingNodeAnnotation(
                category: .other,
                title: "Smaller items",
                explanation: "Combines \(node.itemCount.formatted()) smaller direct entries omitted from this compact view.",
                isComponentRoot: true
            )
        }
        if node.url.standardizedFileURL.path == url.standardizedFileURL.path {
            return AICodingNodeAnnotation(
                category: defaultCategory,
                title: name,
                explanation: explanation,
                isComponentRoot: true
            )
        }

        let rootComponents = url.standardizedFileURL.pathComponents
        let itemComponents = node.url.standardizedFileURL.pathComponents
        guard itemComponents.count >= rootComponents.count else {
            return fallbackAnnotation(for: node)
        }
        let relativeComponents = Array(itemComponents.dropFirst(rootComponents.count))
        guard let rule = rules.enumerated()
            .filter({ $0.element.matches(relativeComponents) })
            .sorted(by: { left, right in
                if left.element.components.count == right.element.components.count {
                    return left.offset < right.offset
                }
                return left.element.components.count > right.element.components.count
            })
            .first?.element else {
            return fallbackAnnotation(for: node)
        }

        let isComponentRoot = relativeComponents.count == rule.components.count
        return AICodingNodeAnnotation(
            category: rule.category,
            title: rule.title,
            explanation: isComponentRoot
                ? rule.explanation
                : "Part of \(rule.title.lowercased()).",
            isComponentRoot: isComponentRoot
        )
    }

    private func fallbackAnnotation(for node: FileNode) -> AICodingNodeAnnotation {
        AICodingNodeAnnotation(
            category: defaultCategory,
            title: defaultCategory.displayName,
            explanation: node.isDirectory
                ? "Folder within \(name)."
                : "File within \(name).",
            isComponentRoot: false
        )
    }
}

struct AICodingToolReport: Identifiable, Equatable, Sendable {
    let tool: AICodingToolMetadata
    let locations: [AICodingStorageLocation]

    init(tool: AICodingToolMetadata, locations: [AICodingStorageLocation]) {
        self.tool = tool
        var seenPaths: Set<String> = []
        self.locations = locations.filter {
            seenPaths.insert($0.url.standardizedFileURL.path).inserted
        }
    }

    var id: AICodingToolID { tool.id }
    var displayName: String { tool.displayName }
    var systemImage: String { tool.systemImage }

    var size: Int64 {
        locations.reduce(0) { partial, location in
            let result = partial.addingReportingOverflow(location.size)
            return result.overflow ? Int64.max : result.partialValue
        }
    }

    var itemCount: Int {
        locations.reduce(0) { partial, location in
            let result = partial.addingReportingOverflow(location.itemCount)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    var latestModificationDate: Date? {
        locations.compactMap(\.latestModificationDate).max()
    }

    var categories: [AICodingCategoryBreakdown] {
        AICodingStorageCategory.allCases.compactMap { category in
            let contributions = locations.compactMap { $0.breakdown(for: category) }
            guard !contributions.isEmpty else { return nil }
            return AICodingCategoryBreakdown(
                category: category,
                size: contributions.reduce(0) { partial, contribution in
                    let result = partial.addingReportingOverflow(contribution.size)
                    return result.overflow ? Int64.max : result.partialValue
                },
                itemCount: contributions.reduce(0) { partial, contribution in
                    let result = partial.addingReportingOverflow(contribution.itemCount)
                    return result.overflow ? Int.max : result.partialValue
                },
                latestModificationDate: contributions.compactMap(\.latestModificationDate).max()
            )
        }
        .filter { $0.size > 0 }
        .sorted {
            if $0.size == $1.size {
                return $0.category.displayName < $1.category.displayName
            }
            return $0.size > $1.size
        }
    }

    var issueCount: Int { locations.count { $0.status.isIssue } }
    var hasMeasuredStorage: Bool { size > 0 }
}

struct AICodingToolsReport: Equatable, Sendable {
    let tools: [AICodingToolReport]
    let startedAt: Date
    let duration: TimeInterval

    var completedAt: Date { startedAt.addingTimeInterval(duration) }

    var totalSize: Int64 {
        uniquePhysicalLocations.reduce(0) { partial, location in
            let result = partial.addingReportingOverflow(location.size)
            return result.overflow ? Int64.max : result.partialValue
        }
    }

    var itemCount: Int {
        uniquePhysicalLocations.reduce(0) { partial, location in
            let result = partial.addingReportingOverflow(location.itemCount)
            return result.overflow ? Int.max : result.partialValue
        }
    }

    var issueCount: Int {
        var seenPaths: Set<String> = []
        return tools.flatMap(\.locations).count { location in
            seenPaths.insert(location.url.standardizedFileURL.path).inserted
                && location.status.isIssue
        }
    }

    var rankedTools: [AICodingToolReport] {
        tools.sorted {
            if $0.size == $1.size { return $0.displayName < $1.displayName }
            return $0.size > $1.size
        }
    }

    private var uniquePhysicalLocations: [AICodingStorageLocation] {
        let ordered = tools.flatMap(\.locations)
            .filter { $0.root != nil || $0.size > 0 }
            .sorted { left, right in
            let leftDepth = left.url.standardizedFileURL.pathComponents.count
            let rightDepth = right.url.standardizedFileURL.pathComponents.count
            if leftDepth == rightDepth {
                return left.url.standardizedFileURL.path < right.url.standardizedFileURL.path
            }
            return leftDepth < rightDepth
            }
        var retained: [AICodingStorageLocation] = []
        for location in ordered {
            let path = location.url.standardizedFileURL.path
            let isContained = retained.contains { existing in
                let parent = existing.url.standardizedFileURL.path
                return path == parent || path.hasPrefix(parent == "/" ? "/" : parent + "/")
            }
            if !isContained { retained.append(location) }
        }
        return retained
    }
}

struct AICodingToolsProgress: Equatable, Sendable {
    var currentTool: AICodingToolMetadata?
    var currentLocationName = ""
    var currentPath = ""
    var completedLocations = 0
    var totalLocations = 0
    var itemsScanned = 0
    var mappedBytes: Int64 = 0

    var fractionCompleted: Double? {
        guard totalLocations > 0 else { return nil }
        return min(max(Double(completedLocations) / Double(totalLocations), 0), 1)
    }
}

enum AICodingToolsAnalysisState: Equatable, Sendable {
    case idle
    case running(previousReport: AICodingToolsReport?)
    case completed(AICodingToolsReport)
    case failed(message: String, previousReport: AICodingToolsReport?)

    var report: AICodingToolsReport? {
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
