import Foundation

struct AICodingToolDefinition: Equatable, Sendable {
    let metadata: AICodingToolMetadata
    let roots: [AICodingRootDescriptor]
    let installation: AICodingInstallationDefinition
}

enum AICodingCatalogSupport {
    static let editorApplicationRules: [AICodingPathRule] = [
        .init(
            "Cache",
            category: .caches,
            title: "Application cache",
            explanation: "Rebuildable application cache data."
        ),
        .init("CachedData", category: .caches),
        .init("Code Cache", category: .caches),
        .init("GPUCache", category: .caches),
        .init("DawnCache", category: .caches),
        .init("DawnGraphiteCache", category: .caches),
        .init("CachedExtensionVSIXs", category: .caches),
        .init("CachedProfilesData", category: .caches),
        .init("Backups", category: .recovery),
        .init(
            "User/History",
            category: .recovery,
            title: "Editor file history",
            explanation: "Editor recovery history for previously edited files."
        ),
        .init(
            "logs",
            category: .logs,
            title: "Application logs",
            explanation: "Diagnostic logs produced while the editor runs."
        ),
        .init("Crashpad", category: .logs),
        .init("sentry", category: .logs),
        .init("User/globalStorage/anysphere.cursor-agent*", category: .extensions)
    ]

    static func root(
        _ toolID: AICodingToolID,
        _ name: String,
        _ url: URL,
        _ explanation: String,
        defaultCategory: AICodingStorageCategory = .other,
        rules: [AICodingPathRule] = [],
        symlinkBoundaryURL: URL? = nil
    ) -> AICodingRootDescriptor {
        AICodingRootDescriptor(
            toolID: toolID,
            name: name,
            url: url,
            explanation: explanation,
            defaultCategory: defaultCategory,
            rules: rules,
            symlinkBoundaryURL: symlinkBoundaryURL
        )
    }

    static func configuredDirectory(
        environmentKey: String,
        request: AICodingToolsRequest
    ) -> URL? {
        guard let path = request.environment[environmentKey], !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true) }
        return request.homeDirectory.appendingPathComponent(path)
    }

    static func absoluteConfiguredDirectory(
        environmentKey: String,
        request: AICodingToolsRequest
    ) -> URL? {
        guard let path = request.environment[environmentKey],
              !path.isEmpty,
              (path as NSString).isAbsolutePath else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func xdgApplicationDirectories(
        environmentKey: String,
        defaultRelativeBase: String,
        applicationDirectory: String,
        request: AICodingToolsRequest
    ) -> [URL] {
        let defaultDirectory = request.homeDirectory
            .appendingPathComponent(defaultRelativeBase, isDirectory: true)
            .appendingPathComponent(applicationDirectory, isDirectory: true)
            .standardizedFileURL
        guard let configuredBase = absoluteConfiguredDirectory(
            environmentKey: environmentKey,
            request: request
        ) else {
            return [defaultDirectory]
        }
        let configuredDirectory = configuredBase
            .appendingPathComponent(applicationDirectory, isDirectory: true)
            .standardizedFileURL
        guard configuredDirectory.path != defaultDirectory.path else {
            return [defaultDirectory]
        }
        return [defaultDirectory, configuredDirectory]
    }
}
