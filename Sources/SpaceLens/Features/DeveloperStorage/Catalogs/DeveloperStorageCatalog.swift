import Foundation

enum DeveloperStorageCatalog {
    static let candidateDirectoryNames: Set<String> = [
        "node_modules", ".next", ".turbo", ".yarn", ".pnpm-store",
        ".venv", "venv", "env", ".tox", ".nox", "__pycache__",
        ".pytest_cache", ".mypy_cache", ".ruff_cache",
        "target", "build", ".gradle",
        ".git", ".hg", ".svn"
    ]

    /// Trees that are either measured separately as shared developer storage or
    /// are unlikely to contain source projects. Pruning them keeps automatic
    /// home-directory discovery bounded and avoids attributing package-manager
    /// internals as projects.
    static let automaticHomePruningDirectoryNames: Set<String> = [
        "Library", "Applications", "Movies", "Music", "Pictures", "Public", ".Trash",
        ".npm", ".cache", ".local", ".nvm", ".bun", ".gradle", ".m2", ".pyenv",
        ".sdkman", ".asdf", ".rustup", ".cargo", ".docker", ".ollama", ".lmstudio"
    ]

    private static let versionControlNames: Set<String> = [".git", ".hg", ".svn"]
    private static let nodeArtifactNames: Set<String> = ["node_modules", ".next", ".turbo", ".yarn", ".pnpm-store"]
    private static let pythonArtifactNames: Set<String> = [".venv", "venv", "env", ".tox", ".nox", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"]
    private static let javaArtifactNames: Set<String> = ["target", "build", ".gradle"]

    static func discoveredDescriptor(
        for candidate: URL,
        inside container: URL,
        request: DeveloperStorageRequest,
        isAutomaticContainer: Bool,
        knownSharedRoots: [URL]
    ) -> DeveloperArtifactDescriptor? {
        let name = candidate.lastPathComponent
        guard !versionControlNames.contains(name), contains(container, candidate) else { return nil }
        guard !knownSharedRoots.contains(where: { contains($0, candidate) }) else { return nil }

        if let managedLocation = toolManagedLocation(containing: candidate, request: request),
           let ecosystemID = ecosystemID(forArtifactNamed: name) {
            let suffix = name == "node_modules" ? "dependencies" : "generated storage"
            return DeveloperArtifactDescriptor(
                ecosystemID: ecosystemID,
                scope: .toolManaged,
                evidence: .toolManagedPath,
                kind: .installedTools,
                name: "\(managedLocation.name) \(suffix)",
                url: candidate,
                symlinkBoundaryURL: managedLocation.url
            )
        }

        if let node = nodeDescriptor(
            for: candidate,
            inside: container,
            isAutomaticContainer: isAutomaticContainer
        ) { return node }
        if let python = pythonDescriptor(for: candidate, inside: container) { return python }
        return javaDescriptor(for: candidate, inside: container)
    }

    static func sharedDescriptors(for request: DeveloperStorageRequest) -> [DeveloperArtifactDescriptor] {
        let home = request.homeDirectory
        var result: [DeveloperArtifactDescriptor] = []

        func add(
            _ ecosystem: DeveloperEcosystemID,
            _ kind: DeveloperArtifactKind,
            _ name: String,
            _ url: URL?,
            rules: [DeveloperArtifactRule] = [],
            boundary: URL? = nil
        ) {
            guard let url, url.path.hasPrefix("/") else { return }
            result.append(
                DeveloperArtifactDescriptor(
                    ecosystemID: ecosystem,
                    scope: .shared,
                    kind: kind,
                    name: name,
                    url: url,
                    rules: rules,
                    symlinkBoundaryURL: boundary ?? url.deletingLastPathComponent()
                )
            )
        }

        // Node.js & Web package stores and installed runtimes.
        add(.nodeAndWeb, .sharedCaches, "npm cache", environmentURL("NPM_CONFIG_CACHE", request), rules: [])
        add(.nodeAndWeb, .sharedCaches, "npm cache", home.appendingPathComponent(".npm"))
        add(.nodeAndWeb, .sharedCaches, "Yarn Berry cache", home.appendingPathComponent(".yarn/berry/cache"))
        add(.nodeAndWeb, .sharedCaches, "Yarn cache", home.appendingPathComponent("Library/Caches/Yarn"))
        add(.nodeAndWeb, .sharedCaches, "Yarn cache", xdgURL("XDG_CACHE_HOME", fallback: home.appendingPathComponent(".cache"), suffix: "yarn", request: request))
        add(.nodeAndWeb, .sharedCaches, "pnpm store", environmentURL("PNPM_STORE_DIR", request))
        add(.nodeAndWeb, .sharedCaches, "pnpm store", xdgURL("XDG_DATA_HOME", fallback: home.appendingPathComponent(".local/share"), suffix: "pnpm/store", request: request))
        add(.nodeAndWeb, .sharedCaches, "pnpm store", home.appendingPathComponent("Library/pnpm/store"))
        add(.nodeAndWeb, .sharedCaches, "Bun install cache", environmentURL("BUN_INSTALL_CACHE_DIR", request))
        add(.nodeAndWeb, .sharedCaches, "Bun install cache", home.appendingPathComponent(".bun/install/cache"))
        add(.nodeAndWeb, .toolchains, "Bun global packages", home.appendingPathComponent(".bun/install/global/node_modules"))
        add(.nodeAndWeb, .toolchains, "NVM Node versions", environmentURL("NVM_DIR", request)?.appendingPathComponent("versions/node"))
        add(.nodeAndWeb, .toolchains, "NVM Node versions", home.appendingPathComponent(".nvm/versions/node"), boundary: home)
        add(.nodeAndWeb, .sharedCaches, "NVM download cache", home.appendingPathComponent(".nvm/.cache"), boundary: home)
        let conventionalNPrefix = home.appendingPathComponent("n", isDirectory: true)
        let nPrefixes = [environmentURL("N_PREFIX", request)]
            .compactMap { $0 }
            + (existsAsDirectory(conventionalNPrefix.appendingPathComponent("n/versions/node"))
                ? [conventionalNPrefix]
                : [])
        var seenNPrefixes: Set<String> = []
        for nPrefix in nPrefixes where seenNPrefixes.insert(nPrefix.standardizedFileURL.path).inserted {
            add(.nodeAndWeb, .toolchains, "n Node versions", nPrefix.appendingPathComponent("n/versions/node"), boundary: nPrefix)
            add(.nodeAndWeb, .installedTools, "n global packages", nPrefix.appendingPathComponent("lib/node_modules"), boundary: nPrefix)
        }
        add(.nodeAndWeb, .toolchains, "fnm Node versions", environmentURL("FNM_DIR", request)?.appendingPathComponent("node-versions"))
        add(.nodeAndWeb, .toolchains, "fnm Node versions", home.appendingPathComponent("Library/Application Support/fnm/node-versions"))
        let volta = environmentURL("VOLTA_HOME", request) ?? home.appendingPathComponent(".volta")
        add(.nodeAndWeb, .toolchains, "Volta Node versions", volta.appendingPathComponent("tools/image/node"), boundary: volta)
        let asdf = environmentURL("ASDF_DATA_DIR", request) ?? home.appendingPathComponent(".asdf")
        add(.nodeAndWeb, .toolchains, "asdf Node versions", asdf.appendingPathComponent("installs/nodejs"), boundary: asdf)
        let mise = environmentURL("MISE_DATA_DIR", request) ?? home.appendingPathComponent(".local/share/mise")
        add(.nodeAndWeb, .toolchains, "mise Node versions", mise.appendingPathComponent("installs/node"), boundary: mise)

        // Python caches, environments, and interpreter installations.
        add(.python, .sharedCaches, "pip cache", environmentURL("PIP_CACHE_DIR", request))
        add(.python, .sharedCaches, "pip cache", home.appendingPathComponent("Library/Caches/pip"))
        add(.python, .sharedCaches, "pip cache", xdgURL("XDG_CACHE_HOME", fallback: home.appendingPathComponent(".cache"), suffix: "pip", request: request))
        for base in ["miniconda3", "anaconda3", "miniforge3", "mambaforge"] {
            let root = home.appendingPathComponent(base)
            add(.python, .sharedCaches, "\(base) packages", root.appendingPathComponent("pkgs"), boundary: root)
            add(.python, .environments, "\(base) environments", root.appendingPathComponent("envs"), boundary: root)
        }
        for environment in condaEnvironmentURLs(home: home) {
            add(.python, .environments, "Conda environment", environment, boundary: environment.deletingLastPathComponent())
        }
        let pyenv = environmentURL("PYENV_ROOT", request) ?? home.appendingPathComponent(".pyenv")
        add(.python, .toolchains, "Pyenv versions", pyenv.appendingPathComponent("versions"), boundary: pyenv)
        let poetryCache = environmentURL("POETRY_CACHE_DIR", request)
            ?? home.appendingPathComponent("Library/Caches/pypoetry")
        add(
            .python,
            .sharedCaches,
            "Poetry data",
            poetryCache,
            rules: [.init("virtualenvs", kind: .environments)],
            boundary: poetryCache.deletingLastPathComponent()
        )
        add(.python, .sharedCaches, "uv cache", environmentURL("UV_CACHE_DIR", request))
        add(.python, .sharedCaches, "uv cache", xdgURL("XDG_CACHE_HOME", fallback: home.appendingPathComponent(".cache"), suffix: "uv", request: request))
        add(.python, .sharedCaches, "uv cache", home.appendingPathComponent("Library/Caches/uv"))
        add(.python, .toolchains, "uv Python versions", environmentURL("UV_PYTHON_INSTALL_DIR", request))
        add(.python, .environments, "uv tools", environmentURL("UV_TOOL_DIR", request))
        let uvData = xdgURL("XDG_DATA_HOME", fallback: home.appendingPathComponent(".local/share"), suffix: "uv", request: request)
        add(.python, .toolchains, "uv Python versions", uvData.appendingPathComponent("python"), boundary: uvData)
        add(.python, .environments, "uv tools", uvData.appendingPathComponent("tools"), boundary: uvData)

        // Java & JVM package stores, build-tool state, and JDKs.
        add(.javaAndJVM, .sharedCaches, "Maven local repository", home.appendingPathComponent(".m2/repository"), boundary: home)
        add(.javaAndJVM, .toolchains, "Maven Wrapper distributions", home.appendingPathComponent(".m2/wrapper/dists"), boundary: home)
        let gradle = environmentURL("GRADLE_USER_HOME", request) ?? home.appendingPathComponent(".gradle")
        add(.javaAndJVM, .sharedCaches, "Gradle caches", gradle.appendingPathComponent("caches"), boundary: gradle)
        add(.javaAndJVM, .toolchains, "Gradle Wrapper distributions", gradle.appendingPathComponent("wrapper/dists"), boundary: gradle)
        add(.javaAndJVM, .toolState, "Gradle daemon data", gradle.appendingPathComponent("daemon"), boundary: gradle)
        add(.javaAndJVM, .toolchains, "Gradle JDKs", gradle.appendingPathComponent("jdks"), boundary: gradle)
        for root in request.systemJDKDirectories {
            add(.javaAndJVM, .toolchains, "Installed JDKs", root, boundary: root.deletingLastPathComponent())
        }
        add(.javaAndJVM, .toolchains, "SDKMAN JDKs", home.appendingPathComponent(".sdkman/candidates/java"), boundary: home)
        add(.javaAndJVM, .toolchains, "asdf Java versions", asdf.appendingPathComponent("installs/java"), boundary: asdf)
        add(.javaAndJVM, .toolchains, "mise Java versions", mise.appendingPathComponent("installs/java"), boundary: mise)
        for prefix in request.homebrewPrefixes {
            let cellar = prefix.appendingPathComponent("Cellar", isDirectory: true)
            for jdk in immediateDirectories(in: cellar, prefix: "openjdk") {
                add(.javaAndJVM, .toolchains, "Homebrew \(jdk.lastPathComponent)", jdk, boundary: cellar)
            }
        }

        return deduplicated(result)
    }

    private static func nodeDescriptor(
        for candidate: URL,
        inside container: URL,
        isAutomaticContainer: Bool
    ) -> DeveloperArtifactDescriptor? {
        let name = candidate.lastPathComponent
        guard nodeArtifactNames.contains(name) else {
            return nil
        }
        let parent = candidate.deletingLastPathComponent()
        let markedProject = nearestProjectRoot(
            from: parent,
            inside: container,
            markers: nodeMarkers
        )
        let versionControlledProject = markedProject == nil
            ? nearestProjectRoot(from: parent, inside: container, markers: Array(versionControlNames))
            : nil
        let selectedProject = !isAutomaticContainer && parent.standardizedFileURL == container.standardizedFileURL
            ? container.standardizedFileURL
            : nil
        let project = markedProject ?? versionControlledProject ?? selectedProject
        let evidence: DeveloperStorageEvidence = if markedProject != nil {
            .projectMarker
        } else if versionControlledProject != nil {
            .versionControl
        } else {
            .selectedFolder
        }

        if name == "node_modules", project == nil {
            return .init(
                ecosystemID: .nodeAndWeb,
                scope: .unattributed,
                evidence: .artifactOnly,
                kind: .projectDependencies,
                name: "Unattributed node_modules",
                url: candidate,
                symlinkBoundaryURL: container
            )
        }
        guard let project else {
            return nil
        }

        switch name {
        case "node_modules":
            return .init(
                ecosystemID: .nodeAndWeb,
                scope: .project,
                evidence: evidence,
                kind: .projectDependencies,
                name: "node_modules",
                url: candidate,
                projectURL: project,
                rules: [
                    .init(".vite", kind: .projectCaches),
                    .init(".cache/turbo", kind: .projectCaches),
                    .init(".pnpm-store", kind: .sharedCaches)
                ],
                symlinkBoundaryURL: project
            )
        case ".next":
            return .init(ecosystemID: .nodeAndWeb, scope: .project, evidence: evidence, kind: .buildOutputs, name: "Next.js output", url: candidate, projectURL: project, rules: [.init("cache", kind: .projectCaches)], symlinkBoundaryURL: project)
        case ".turbo":
            return .init(ecosystemID: .nodeAndWeb, scope: .project, evidence: evidence, kind: .projectCaches, name: "Turbo cache", url: candidate, projectURL: project, symlinkBoundaryURL: project)
        case ".yarn":
            let cache = candidate.appendingPathComponent("cache", isDirectory: true)
            guard existsAsDirectory(cache) else { return nil }
            return .init(ecosystemID: .nodeAndWeb, scope: .project, evidence: evidence, kind: .projectCaches, name: "Yarn project cache", url: cache, projectURL: project, symlinkBoundaryURL: project)
        default:
            return .init(ecosystemID: .nodeAndWeb, scope: .project, evidence: evidence, kind: .sharedCaches, name: "Project pnpm store", url: candidate, projectURL: project, symlinkBoundaryURL: project)
        }
    }

    private static func pythonDescriptor(for candidate: URL, inside container: URL) -> DeveloperArtifactDescriptor? {
        let name = candidate.lastPathComponent
        let parent = candidate.deletingLastPathComponent()
        if [".venv", "venv", "env"].contains(name) {
            guard exists(candidate.appendingPathComponent("pyvenv.cfg")),
                  exists(candidate.appendingPathComponent("bin/python")) else { return nil }
            let markedProject = nearestProjectRoot(from: parent, inside: container, markers: pythonMarkers)
            let project = markedProject ?? parent
            return .init(ecosystemID: .python, scope: .project, evidence: markedProject == nil ? .artifactSignature : .projectMarker, kind: .environments, name: "Python environment", url: candidate, projectURL: project, symlinkBoundaryURL: project)
        }
        if [".tox", ".nox"].contains(name) {
            guard let project = nearestProjectRoot(from: parent, inside: container, markers: pythonMarkers) else { return nil }
            return .init(ecosystemID: .python, scope: .project, kind: .environments, name: name == ".tox" ? "tox environments" : "nox environments", url: candidate, projectURL: project, symlinkBoundaryURL: project)
        }
        guard ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"].contains(name),
              let project = nearestProjectRoot(from: parent, inside: container, markers: pythonMarkers) else { return nil }
        return .init(ecosystemID: .python, scope: .project, kind: .projectCaches, name: name, url: candidate, projectURL: project, symlinkBoundaryURL: project)
    }

    private static func javaDescriptor(for candidate: URL, inside container: URL) -> DeveloperArtifactDescriptor? {
        let name = candidate.lastPathComponent
        let parent = candidate.deletingLastPathComponent()
        if name == "target", exists(parent.appendingPathComponent("pom.xml")) {
            return .init(ecosystemID: .javaAndJVM, scope: .project, kind: .buildOutputs, name: "Maven target", url: candidate, projectURL: parent, symlinkBoundaryURL: parent)
        }
        if ["build", ".gradle"].contains(name),
           let project = nearestProjectRoot(from: parent, inside: container, markers: gradleMarkers) {
            return .init(
                ecosystemID: .javaAndJVM,
                scope: .project,
                kind: name == "build" ? .buildOutputs : .projectCaches,
                name: name == "build" ? "Gradle build output" : "Gradle project cache",
                url: candidate,
                projectURL: project,
                symlinkBoundaryURL: project
            )
        }
        return nil
    }

    private static let nodeMarkers = ["package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock"]
    private static let pythonMarkers = ["pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "tox.ini", "noxfile.py"]
    private static let gradleMarkers = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]

    private static func toolManagedLocation(
        containing candidate: URL,
        request: DeveloperStorageRequest
    ) -> DeveloperManagedLocation? {
        let home = request.homeDirectory
        let configHome = environmentURL("XDG_CONFIG_HOME", request)
            ?? home.appendingPathComponent(".config", isDirectory: true)
        let locations = [
            DeveloperManagedLocation(name: "Claude plugin", url: home.appendingPathComponent(".claude/plugins", isDirectory: true)),
            DeveloperManagedLocation(name: "Claude installation", url: home.appendingPathComponent(".claude/local", isDirectory: true)),
            DeveloperManagedLocation(name: "Gemini extension", url: home.appendingPathComponent(".gemini/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Antigravity data", url: home.appendingPathComponent(".gemini/antigravity", isDirectory: true)),
            DeveloperManagedLocation(name: "Antigravity CLI data", url: home.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)),
            DeveloperManagedLocation(name: "VS Code extension", url: home.appendingPathComponent(".vscode/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "VS Code Insiders extension", url: home.appendingPathComponent(".vscode-insiders/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "VS Code server extension", url: home.appendingPathComponent(".vscode-server/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Cursor extension", url: home.appendingPathComponent(".cursor/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Cursor server extension", url: home.appendingPathComponent(".cursor-server/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Kiro extension", url: home.appendingPathComponent(".kiro/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Kiro server extension", url: home.appendingPathComponent(".kiro-server/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Windsurf extension", url: home.appendingPathComponent(".windsurf/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Codex plugin", url: home.appendingPathComponent(".codex/plugins", isDirectory: true)),
            DeveloperManagedLocation(name: "Antigravity extension", url: home.appendingPathComponent(".antigravity/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Antigravity IDE extension", url: home.appendingPathComponent(".antigravity-ide/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "Antigravity extension", url: home.appendingPathComponent(".antigravity-server/extensions", isDirectory: true)),
            DeveloperManagedLocation(name: "OpenCode installation", url: home.appendingPathComponent(".opencode", isDirectory: true)),
            DeveloperManagedLocation(name: "OpenCode configuration", url: configHome.appendingPathComponent("opencode", isDirectory: true)),
            DeveloperManagedLocation(name: "Kilo configuration", url: configHome.appendingPathComponent("kilo", isDirectory: true))
        ]
        return locations
            .filter { contains($0.url, candidate) }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }
    }

    private static func ecosystemID(forArtifactNamed name: String) -> DeveloperEcosystemID? {
        if nodeArtifactNames.contains(name) { return .nodeAndWeb }
        if pythonArtifactNames.contains(name) { return .python }
        if javaArtifactNames.contains(name) { return .javaAndJVM }
        return nil
    }

    private static func nearestProjectRoot(from start: URL, inside container: URL, markers: [String]) -> URL? {
        var candidate = start.standardizedFileURL
        let root = container.standardizedFileURL
        while contains(root, candidate) {
            if markers.contains(where: { exists(candidate.appendingPathComponent($0)) }) { return candidate }
            if candidate.path == root.path { break }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent.path == candidate.path { break }
            candidate = parent
        }
        return nil
    }

    private static func environmentURL(_ key: String, _ request: DeveloperStorageRequest) -> URL? {
        guard let value = request.environment[key], value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }

    private static func xdgURL(
        _ key: String,
        fallback: URL,
        suffix: String,
        request: DeveloperStorageRequest
    ) -> URL {
        (environmentURL(key, request) ?? fallback).appendingPathComponent(suffix, isDirectory: true)
    }

    private static func condaEnvironmentURLs(home: URL) -> [URL] {
        let index = home.appendingPathComponent(".conda/environments.txt")
        guard let handle = try? FileHandle(forReadingFrom: index) else { return [] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 1_048_576)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            return exists(url.appendingPathComponent("conda-meta", isDirectory: true)) ? url : nil
        }
    }

    private static func immediateDirectories(in root: URL, prefix: String) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter {
            guard $0.lastPathComponent.hasPrefix(prefix),
                  let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
    }

    private static func deduplicated(_ descriptors: [DeveloperArtifactDescriptor]) -> [DeveloperArtifactDescriptor] {
        var seen: Set<String> = []
        return descriptors.filter { seen.insert($0.id).inserted }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func existsAsDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        if parentPath == childPath { return true }
        if parentPath == "/" { return childPath.hasPrefix("/") }
        return childPath.hasPrefix(parentPath + "/")
    }
}

private struct DeveloperManagedLocation: Sendable {
    let name: String
    let url: URL
}
