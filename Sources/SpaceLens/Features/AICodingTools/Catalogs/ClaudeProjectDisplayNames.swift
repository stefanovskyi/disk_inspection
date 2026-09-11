import Foundation

enum ClaudeProjectDisplayNames {
    static let maximumRegistrySize = 1_048_576

    static func load(
        homeDirectory: URL,
        claudeDirectory: URL,
        fileManager: FileManager = .default
    ) -> [String: String] {
        let projectDirectory = claudeDirectory.appendingPathComponent("projects", isDirectory: true)
        let directoryNames = (try? fileManager.contentsOfDirectory(atPath: projectDirectory.path)) ?? []
        guard !directoryNames.isEmpty else { return [:] }

        let registryURL = homeDirectory.appendingPathComponent(".claude.json", isDirectory: false)
        let registeredProjectPaths = registeredProjectPaths(
            at: registryURL,
            fileManager: fileManager
        )
        return overrides(
            projectDirectory: projectDirectory,
            directoryNames: directoryNames,
            registeredProjectPaths: registeredProjectPaths,
            homeDirectory: homeDirectory
        )
    }

    static func overrides(
        projectDirectory: URL,
        directoryNames: [String],
        registeredProjectPaths: [String],
        homeDirectory: URL
    ) -> [String: String] {
        let pathsByDirectoryName = Dictionary(grouping: registeredProjectPaths) {
            encodedDirectoryName(for: $0)
        }
        var result: [String: String] = [:]

        for directoryName in directoryNames {
            let registeredNames = Set(
                (pathsByDirectoryName[directoryName] ?? []).compactMap { path in
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    return name.isEmpty ? nil : name
                }
            )
            let friendlyName: String?
            if registeredNames.count == 1 {
                friendlyName = registeredNames.first
            } else {
                friendlyName = fallbackFriendlyName(
                    for: directoryName,
                    homeDirectory: homeDirectory
                )
            }

            guard let friendlyName, !friendlyName.isEmpty, friendlyName != directoryName else {
                continue
            }
            let nodePath = projectDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
                .standardizedFileURL.path
            result[nodePath] = "\(friendlyName) (\(directoryName))"
        }
        return result
    }

    static func encodedDirectoryName(for projectPath: String) -> String {
        String(projectPath.map { character in
            character.isLetter || character.isNumber ? character : "-"
        })
    }

    private static func registeredProjectPaths(
        at url: URL,
        fileManager: FileManager
    ) -> [String] {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumRegistrySize,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count <= maximumRegistrySize,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let projects = dictionary["projects"] as? [String: Any] else {
            return []
        }
        return Array(projects.keys)
    }

    private static func fallbackFriendlyName(
        for directoryName: String,
        homeDirectory: URL
    ) -> String? {
        let homeKey = encodedDirectoryName(for: homeDirectory.standardizedFileURL.path)
        if directoryName == homeKey {
            let name = homeDirectory.lastPathComponent
            return name.isEmpty ? nil : name
        }

        let homePrefix = homeKey + "-"
        guard directoryName.hasPrefix(homePrefix) else { return nil }
        var suffix = String(directoryName.dropFirst(homePrefix.count))
        for conventionalPrefix in ["Documents-projects-", "Documents-Projects-"]
        where suffix.hasPrefix(conventionalPrefix) {
            suffix.removeFirst(conventionalPrefix.count)
            break
        }
        return suffix.isEmpty ? nil : suffix
    }
}
