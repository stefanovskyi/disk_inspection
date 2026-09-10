import Foundation

struct AICodingRootDescriptor: Equatable, Sendable {
    let toolID: AICodingToolID
    let name: String
    let url: URL
    let explanation: String
    let defaultCategory: AICodingStorageCategory
    let rules: [AICodingPathRule]
    let symlinkBoundaryURL: URL?

    init(
        toolID: AICodingToolID,
        name: String,
        url: URL,
        explanation: String,
        defaultCategory: AICodingStorageCategory,
        rules: [AICodingPathRule],
        symlinkBoundaryURL: URL? = nil
    ) {
        self.toolID = toolID
        self.name = name
        self.url = url
        self.explanation = explanation
        self.defaultCategory = defaultCategory
        self.rules = rules
        self.symlinkBoundaryURL = symlinkBoundaryURL
    }

    var id: String { "\(toolID.rawValue)|\(url.standardizedFileURL.path)" }

    func category(for itemURL: URL) -> AICodingStorageCategory {
        let rootComponents = url.standardizedFileURL.pathComponents
        let itemComponents = itemURL.standardizedFileURL.pathComponents
        guard itemComponents.count >= rootComponents.count else { return defaultCategory }
        let relativeComponents = Array(itemComponents.dropFirst(rootComponents.count))
        return rules.enumerated()
            .filter { $0.element.matches(relativeComponents) }
            .sorted { left, right in
                if left.element.components.count == right.element.components.count {
                    return left.offset < right.offset
                }
                return left.element.components.count > right.element.components.count
            }
            .first?
            .element.category ?? defaultCategory
    }

    func standardized() -> Self {
        Self(
            toolID: toolID,
            name: name,
            url: url.standardizedFileURL,
            explanation: explanation,
            defaultCategory: defaultCategory,
            rules: rules,
            symlinkBoundaryURL: symlinkBoundaryURL?.standardizedFileURL
        )
    }

    func absorbing(_ nested: Self) -> Self {
        guard toolID == nested.toolID,
              AICodingToolsAnalyzer.contains(url, nested.url),
              url.standardizedFileURL.path != nested.url.standardizedFileURL.path else {
            return self
        }
        let rootComponents = url.standardizedFileURL.pathComponents
        let nestedComponents = nested.url.standardizedFileURL.pathComponents
        let prefix = Array(nestedComponents.dropFirst(rootComponents.count))
        let nestedRootRule = AICodingPathRule(
            prefix.joined(separator: "/"),
            category: nested.defaultCategory,
            title: nested.name,
            explanation: nested.explanation
        )
        let rebasedRules = nested.rules.map { $0.prefixing(prefix) }
        let additions = [nestedRootRule] + rebasedRules
        let mergedRules = rules + additions.filter { !rules.contains($0) }
        return Self(
            toolID: toolID,
            name: name,
            url: url,
            explanation: explanation,
            defaultCategory: defaultCategory,
            rules: mergedRules,
            symlinkBoundaryURL: symlinkBoundaryURL
        )
    }
}
