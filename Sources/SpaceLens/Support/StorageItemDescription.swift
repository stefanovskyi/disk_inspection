import Foundation

/// A short, universal explanation of a well-known file or folder.
struct StorageItemDescription: Equatable, Sendable {
    enum Safety: Equatable, Sendable {
        /// Deleting costs only time: the contents are rebuilt or downloaded again.
        case safeToClear
        /// May hold data the user wants; deleting works but has consequences.
        case reviewFirst
        /// Deleting breaks macOS, an application, or access to something.
        case keep

        var label: String {
            switch self {
            case .safeToClear: return "Safe to clear"
            case .reviewFirst: return "Review before deleting"
            case .keep: return "Do not delete"
            }
        }

        var symbolName: String {
            switch self {
            case .safeToClear: return "checkmark.circle.fill"
            case .reviewFirst: return "exclamationmark.circle.fill"
            case .keep: return "hand.raised.fill"
            }
        }
    }

    let safety: Safety
    let text: String

    static func safe(_ text: String) -> Self { Self(safety: .safeToClear, text: text) }
    static func review(_ text: String) -> Self { Self(safety: .reviewFirst, text: text) }
    static func keep(_ text: String) -> Self { Self(safety: .keep, text: text) }

    /// Matches only where a location's meaning is certain, so a project folder
    /// named `Library` or `Caches` stays undescribed.
    static func resolve(url: URL, isDirectory: Bool) -> Self? {
        typealias Catalog = StorageItemDescriptionCatalog

        let path = canonicalPath(of: url)
        if let description = Catalog.absolutePaths[path] { return description }

        let homeRelativePath = homeRelative(path)
        if let homeRelativePath {
            if homeRelativePath.isEmpty { return Catalog.homeFolder }
            if let description = Catalog.homePaths[homeRelativePath] { return description }
        }

        let name = (path as NSString).lastPathComponent
        if let description = isDirectory ? Catalog.directoryNames[name] : Catalog.fileNames[name] {
            return description
        }
        // Before extensions: "Caches/com.example.app" is a bundle identifier, not an application.
        if isDirectory {
            let parent = (path as NSString).deletingLastPathComponent
            let description = homeRelative(parent).flatMap { Catalog.homeChildren[$0] }
                ?? Catalog.absoluteChildren[parent]
            if let description { return description }
        }
        let pathExtension = (name as NSString).pathExtension.lowercased()
        if isDirectory, pathExtension == "app" {
            return path.hasPrefix("/System/") ? Catalog.builtInApplication : Catalog.application
        }
        if let description = isDirectory
            ? Catalog.directoryExtensions[pathExtension]
            : Catalog.fileExtensions[pathExtension] {
            return description
        }
        return Catalog.subtrees.first { path.hasPrefix($0.prefix) }?.description
    }

    /// One spelling per location: firmlinks and the root symlinks into `/private`
    /// lead to the same data as their canonical paths.
    private static func canonicalPath(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        let dataVolume = "/System/Volumes/Data"
        if path == dataVolume { return "/" }
        if path.hasPrefix(dataVolume + "/") { return String(path.dropFirst(dataVolume.count)) }
        for link in ["/var", "/tmp", "/etc"] where path == link || path.hasPrefix(link + "/") {
            return "/private" + path
        }
        return path
    }

    /// The path below a user's home folder, or nil outside of any home folder.
    private static func homeRelative(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2, components[0] == "Users", components[1] != "Shared" else { return nil }
        return components.dropFirst(2).joined(separator: "/")
    }
}
