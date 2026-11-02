import Foundation

/// Where macOS can supply a real icon, read through Launch Services.
enum SystemIconSource: Hashable, Sendable {
    case file(URL)
    case bundleIdentifier(String)
    case applicationNamed(String)
    case fileType(String)

    /// Helpers and extensions extend their application's identifier, so
    /// "com.hnc.Discord.ShipIt" belongs to "com.hnc.Discord".
    static func bundleIdentifierCandidates(for identifier: String) -> [String] {
        let components = identifier.split(separator: ".")
        guard components.count >= 2 else { return [] }
        return (2...components.count).reversed().map {
            components.prefix($0).joined(separator: ".")
        }
    }
}

/// How a scanned file or folder is identified in storage lists.
enum StorageItemIcon: Equatable, Sendable {
    /// A real macOS icon, or the logo when the system has none to offer.
    case system(SystemIconSource, fallback: BrandLogo?)
    case brand(BrandLogo)
    case generic

    /// Library folders named after the application that owns their contents.
    private static let applicationNamedParents: Set<String> = ["Application Support", "Caches", "Logs"]
    private static let bundleIdentifiedParents: Set<String> = [
        "Application Scripts", "Application Support", "Caches", "Containers", "Group Containers",
        "HTTPStorages", "Logs", "Preferences", "Saved Application State", "WebKit"
    ]
    /// Folders whose direct children are named after a tool.
    private static let productParents: Set<String> = [
        ".cache", ".config", "Library", "Preferences", "Cellar", "Caskroom"
    ]
    private static let packageParents: Set<String> = ["node_modules", "site-packages", "dist-packages"]
    private static let bundleIdentifierFileSuffixes = [".plist", ".savedState", ".binarycookies"]
    /// Folder names that differ from the name of the application that owns them.
    private static let applicationNameAliases = [
        "Code": "Visual Studio Code", "Docker Desktop": "Docker", "iTerm2": "iTerm",
        "BraveSoftware": "Brave Browser", "Mozilla": "Firefox", "Sublime Text 3": "Sublime Text",
        "Google": "Google Chrome", "OpenAI": "ChatGPT", "obs-studio": "OBS", "Mega Limited": "MEGAsync",
        "ViberPC": "Viber", "Logi": "logioptionsplus", "Claude-3p": "Claude", "t3code-v2": "T3 Code (Beta)"
    ]
    /// Library folders owned by applications with a different name.
    private static let libraryApplications = [
        "Mail": "Mail", "Safari": "Safari", "Messages": "Messages", "Photos": "Photos",
        "Calendars": "Calendar", "Reminders": "Reminders", "Contacts": "Contacts", "Maps": "Maps",
        "News": "News", "Weather": "Weather", "Shortcuts": "Shortcuts", "Fonts": "Font Book",
        "Keychains": "Utilities/Keychain Access", "iMovie": "iMovie"
    ]
    /// Standard folders that macOS draws with their own glyph.
    private static let homeSystemFolders: Set<String> = [
        "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Sites"
    ]
    private static let rootSystemFolders: Set<String> = ["Applications", "Library", "System", "Users", "Volumes"]
    /// Folder extensions that macOS treats as single documents with their own icon.
    private static let packageExtensions: Set<String> = [
        "framework", "bundle", "plugin", "kext", "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary",
        "fcpbundle", "logicx", "band", "sparsebundle", "pages", "numbers", "key", "rtfd", "xcassets", "docset"
    ]

    static func resolve(url: URL, isDirectory: Bool) -> Self {
        let name = url.lastPathComponent
        let parentURL = url.deletingLastPathComponent()
        let parent = parentURL.lastPathComponent
        let item = BrandLogoCatalog.logo(forItemNamed: name, isDirectory: isDirectory)
        let product = BrandLogoCatalog.logo(forProductNamed: name)

        if name.lowercased().hasSuffix(".app") {
            let stem = BrandLogoCatalog.logo(forProductNamed: (name as NSString).deletingPathExtension)
            if isDirectory { return .system(.file(url), fallback: stem) }
            return stem.map(Self.brand) ?? .generic
        }
        if isDirectory, isSystemFolder(url) {
            return .system(.file(url), fallback: nil)
        }
        if isDirectory, parent == "Library", let application = libraryApplications[name] {
            return .system(.applicationNamed(application), fallback: product)
        }
        if bundleIdentifiedParents.contains(parent), let identifier = bundleIdentifier(in: name, isDirectory: isDirectory) {
            let vendor = BrandLogoCatalog.logo(forBundleIdentifier: identifier)
            return .system(.bundleIdentifier(identifier), fallback: vendor ?? product ?? item)
        }
        if parent == "Group Containers", let team = name.split(separator: ".").first,
           let logo = BrandLogoCatalog.logo(forTeamIdentifier: String(team)) {
            return .brand(logo)
        }
        if isDirectory, applicationNamedParents.contains(parent), !name.hasPrefix(".") {
            return .system(
                .applicationNamed(applicationNameAliases[name] ?? name),
                fallback: applicationFolderLogo(name) ?? product ?? item
            )
        }
        // Applications often ship inside a folder of the same name.
        if isDirectory, parent == "Applications" {
            return .system(.applicationNamed("\(name)/\(name)"), fallback: product)
        }
        if packageParents.contains(parent) || name.hasPrefix("@") {
            return BrandLogoCatalog.logo(forPackageNamed: name).map(Self.brand) ?? item.map(Self.brand) ?? .generic
        }
        if parent.hasPrefix("@"), parentURL.deletingLastPathComponent().lastPathComponent == "node_modules",
           let logo = BrandLogoCatalog.logo(forPackageNamed: parent) {
            return .brand(logo)
        }
        if name.hasPrefix(".") || productParents.contains(parent) || isLocalShare(parentURL), let product {
            return .brand(product)
        }
        if isDirectory, isHomeFolder(parentURL), let logo = BrandLogoCatalog.logo(forHomeFolderNamed: name) {
            return .brand(logo)
        }
        if let item {
            return .brand(item)
        }

        let pathExtension = (name as NSString).pathExtension.lowercased()
        if !pathExtension.isEmpty, !isDirectory || packageExtensions.contains(pathExtension) {
            return .system(.fileType(pathExtension), fallback: nil)
        }
        return .generic
    }

    /// "Claude" is the desktop app's data, while ".claude" and "claude" belong to Claude Code.
    private static func applicationFolderLogo(_ name: String) -> BrandLogo? {
        name == "Claude" ? .claude : nil
    }

    private static func isLocalShare(_ url: URL) -> Bool {
        url.lastPathComponent == "share" && url.deletingLastPathComponent().lastPathComponent == ".local"
    }

    private static func isHomeFolder(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        return components.count == 3 && components[1] == "Users"
    }

    private static func isSystemFolder(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        if parent.path == "/" { return rootSystemFolders.contains(url.lastPathComponent) }
        return isHomeFolder(parent) && homeSystemFolders.contains(url.lastPathComponent)
    }

    /// The bundle identifier in a Library item's name, without any Apple Developer
    /// team or App Group prefix: "UBF8T346G9.com.microsoft.teams", "group.com.x.app".
    private static func bundleIdentifier(in name: String, isDirectory: Bool) -> String? {
        var identifier = name
        if !isDirectory {
            guard let suffix = bundleIdentifierFileSuffixes.first(where: name.hasSuffix) else { return nil }
            identifier.removeLast(suffix.count)
        }
        var components = identifier.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        while let first = components.first,
              first == "group" || first == "groups" || isTeamIdentifier(first) {
            components.removeFirst()
        }
        guard components.count >= 2, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        identifier = components.joined(separator: ".")
        let isValid = identifier.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" || $0 == " " || $0 == "$")
        }
        return isValid ? identifier : nil
    }

    private static func isTeamIdentifier(_ component: String) -> Bool {
        component.count == 10 && component.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
}
