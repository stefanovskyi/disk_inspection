import Foundation

struct AIModelsAndRuntimesRequest: Sendable {
    let homeDirectory: URL
    let applicationSupportDirectory: URL
    let environment: [String: String]
    let applicationDirectories: [URL]
    let homebrewPrefixes: [URL]
    let additionalModelRoots: [URL]

    init(
        homeDirectory: URL,
        applicationSupportDirectory: URL,
        environment: [String: String],
        applicationDirectories: [URL] = [],
        homebrewPrefixes: [URL] = [],
        additionalModelRoots: [URL] = []
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.applicationSupportDirectory = applicationSupportDirectory.standardizedFileURL
        self.environment = environment
        self.applicationDirectories = applicationDirectories.map(\.standardizedFileURL)
        self.homebrewPrefixes = homebrewPrefixes.map(\.standardizedFileURL)
        self.additionalModelRoots = additionalModelRoots.map(\.standardizedFileURL)
    }

    static func currentUser(additionalModelRoots: [URL] = []) -> Self {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return Self(
            homeDirectory: home,
            applicationSupportDirectory: appSupport,
            environment: ProcessInfo.processInfo.environment,
            applicationDirectories: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true)
            ],
            homebrewPrefixes: [
                URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
                URL(fileURLWithPath: "/usr/local", isDirectory: true)
            ],
            additionalModelRoots: additionalModelRoots
        )
    }
}

enum AIModelRootPurpose: Equatable, Sendable {
    case managed
    case installation
    case standaloneSearch
}

struct AIModelRootDescriptor: Identifiable, Equatable, Sendable {
    let runtimeID: AIModelRuntimeID
    let name: String
    let url: URL
    let purpose: AIModelRootPurpose
    let modelRoot: URL?
    let excludedManagedRoots: [URL]

    init(
        runtimeID: AIModelRuntimeID,
        name: String,
        url: URL,
        purpose: AIModelRootPurpose,
        modelRoot: URL? = nil,
        excludedManagedRoots: [URL] = []
    ) {
        self.runtimeID = runtimeID
        self.name = name
        self.url = url.standardizedFileURL
        self.purpose = purpose
        self.modelRoot = modelRoot?.standardizedFileURL
        self.excludedManagedRoots = excludedManagedRoots.map(\.standardizedFileURL)
    }

    var id: String { "\(runtimeID.rawValue)|\(url.path)" }

    func includes(_ itemURL: URL) -> Bool {
        !excludedManagedRoots.contains { AIModelsDiscovery.contains($0, itemURL) }
    }
}

struct AIModelsDiscoveryResult: Sendable {
    let roots: [AIModelRootDescriptor]
    let installations: [AIModelRuntimeID: [AIModelRuntimeInstallation]]
}

enum AIModelsDiscovery {
    static func discover(request: AIModelsAndRuntimesRequest) -> AIModelsDiscoveryResult {
        let fileManager = FileManager.default
        let home = request.homeDirectory
        let lmStudioHomes = lmStudioHomes(request: request)
        let lmStudioModelRoots = lmStudioHomes.map { lmStudioHome in
            configuredLMStudioModelRoot(home: lmStudioHome)
                ?? lmStudioHome.appendingPathComponent("models", isDirectory: true)
        }
        let ollamaModelRoot = absoluteEnvironmentURL("OLLAMA_MODELS", request: request)
            ?? home.appendingPathComponent(".ollama/models", isDirectory: true)
        let huggingFaceRoot = huggingFaceHubRoot(request: request)

        var installations: [AIModelRuntimeID: [AIModelRuntimeInstallation]] = [:]
        installations[.ollama] = applicationInstallations(
            runtimeID: .ollama,
            bundleNames: ["Ollama.app"],
            request: request
        ) + commandInstallations(
            runtimeID: .ollama,
            commandNames: ["ollama"],
            extraCandidates: [URL(fileURLWithPath: "/usr/local/bin/ollama")],
            request: request
        )
        installations[.lmStudio] = applicationInstallations(
            runtimeID: .lmStudio,
            bundleNames: ["LM Studio.app"],
            request: request
        ) + commandInstallations(
            runtimeID: .lmStudio,
            commandNames: ["lms"],
            extraCandidates: lmStudioHomes.map { $0.appendingPathComponent("bin/lms") } + [
                URL(fileURLWithPath: "/usr/local/bin/lms"),
                URL(fileURLWithPath: "/opt/homebrew/bin/lms")
            ],
            request: request
        )
        installations[.llamaCpp] = llamaCppInstallations(request: request)
        installations[.huggingFace] = commandInstallations(
            runtimeID: .huggingFace,
            commandNames: ["hf", "huggingface-cli"],
            extraCandidates: [],
            request: request
        )
        installations[.standalone] = []

        var managedRoots: [AIModelRootDescriptor] = []
        let ollamaHome = home.appendingPathComponent(".ollama", isDirectory: true)
        if itemExists(ollamaHome) {
            managedRoots.append(.init(
                runtimeID: .ollama,
                name: "Ollama data",
                url: ollamaHome,
                purpose: .managed,
                modelRoot: AIModelsDiscovery.contains(ollamaHome, ollamaModelRoot) ? ollamaModelRoot : nil
            ))
        }
        if itemExists(ollamaModelRoot), !AIModelsDiscovery.contains(ollamaHome, ollamaModelRoot) {
            managedRoots.append(.init(
                runtimeID: .ollama,
                name: "Ollama models",
                url: ollamaModelRoot,
                purpose: .managed,
                modelRoot: ollamaModelRoot
            ))
        }

        for (index, lmStudioHome) in lmStudioHomes.enumerated() {
            let lmStudioModelRoot = lmStudioModelRoots[index]
            if itemExists(lmStudioHome) {
                managedRoots.append(.init(
                    runtimeID: .lmStudio,
                    name: index == 0 ? "LM Studio active home" : "LM Studio legacy home",
                    url: lmStudioHome,
                    purpose: .managed,
                    modelRoot: AIModelsDiscovery.contains(lmStudioHome, lmStudioModelRoot)
                        ? lmStudioModelRoot : nil
                ))
            }
            if itemExists(lmStudioModelRoot), !AIModelsDiscovery.contains(lmStudioHome, lmStudioModelRoot) {
                managedRoots.append(.init(
                    runtimeID: .lmStudio,
                    name: "LM Studio models",
                    url: lmStudioModelRoot,
                    purpose: .managed,
                    modelRoot: lmStudioModelRoot
                ))
            }
        }
        let lmAppSupport = request.applicationSupportDirectory
            .appendingPathComponent("LM Studio", isDirectory: true)
        if itemExists(lmAppSupport) {
            managedRoots.append(.init(
                runtimeID: .lmStudio,
                name: "LM Studio app support",
                url: lmAppSupport,
                purpose: .managed
            ))
        }

        if itemExists(huggingFaceRoot) {
            managedRoots.append(.init(
                runtimeID: .huggingFace,
                name: "Hugging Face Hub cache",
                url: huggingFaceRoot,
                purpose: .managed,
                modelRoot: huggingFaceRoot
            ))
        }

        for installation in installations.values.flatMap({ $0 }) {
            let storageURL: URL
            if installation.kind == .application {
                storageURL = installation.url
            } else if installation.runtimeID == .llamaCpp {
                storageURL = installation.url
            } else {
                continue
            }
            guard itemExists(storageURL) else { continue }
            managedRoots.append(.init(
                runtimeID: installation.runtimeID,
                name: installation.name,
                url: storageURL,
                purpose: .installation
            ))
        }

        managedRoots = normalizedRoots(managedRoots)
        let managedURLs = managedRoots.map(\.url)
        let defaultStandaloneRoots = [
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Desktop", isDirectory: true)
        ]
        let standaloneRoots = normalizedURLs(defaultStandaloneRoots + request.additionalModelRoots)
            .filter(itemExists)
            .filter { candidate in
                !managedURLs.contains { contains($0, candidate) }
            }
            .map { url in
                AIModelRootDescriptor(
                    runtimeID: .standalone,
                    name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                    url: url,
                    purpose: .standaloneSearch,
                    excludedManagedRoots: managedURLs.filter { contains(url, $0) }
                )
            }

        let roots = normalizedRoots(managedRoots + standaloneRoots).filter {
            fileManager.fileExists(atPath: $0.url.path)
        }
        return AIModelsDiscoveryResult(roots: roots, installations: installations)
    }

    static func lmStudioHome(request: AIModelsAndRuntimesRequest) -> URL {
        lmStudioHomes(request: request)[0]
    }

    private static func lmStudioHomes(request: AIModelsAndRuntimesRequest) -> [URL] {
        let pointer = request.homeDirectory.appendingPathComponent(".lmstudio-home-pointer")
        var candidates: [URL] = []
        if let value = AIModelInventoryParsers.boundedString(at: pointer), value.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: value, isDirectory: true))
        }
        let legacy = request.homeDirectory.appendingPathComponent(".cache/lm-studio", isDirectory: true)
        let current = request.homeDirectory.appendingPathComponent(".lmstudio", isDirectory: true)
        candidates.append(contentsOf: [legacy, current])
        let existing = normalizedURLs(candidates).filter(itemExists)
        return existing.isEmpty ? [current.standardizedFileURL] : existing
    }

    static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        if parentPath == childPath { return true }
        if parentPath == "/" { return childPath.hasPrefix("/") }
        return childPath.hasPrefix(parentPath + "/")
    }

    private static func configuredLMStudioModelRoot(home: URL) -> URL? {
        guard let settings = AIModelInventoryParsers.jsonObject(
            at: home.appendingPathComponent("settings.json")
        ) else { return nil }
        let values = [
            settings["downloadsFolder"] as? String,
            settings["modelsDirectory"] as? String,
            (settings["paths"] as? [String: Any])?["models"] as? String
        ]
        guard let raw = values.compactMap({ $0 }).first, raw.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
    }

    private static func huggingFaceHubRoot(request: AIModelsAndRuntimesRequest) -> URL {
        if let direct = absoluteEnvironmentURL("HF_HUB_CACHE", request: request)
            ?? absoluteEnvironmentURL("HUGGINGFACE_HUB_CACHE", request: request) {
            return direct
        }
        if let hfHome = absoluteEnvironmentURL("HF_HOME", request: request) {
            return hfHome.appendingPathComponent("hub", isDirectory: true)
        }
        if let xdg = absoluteEnvironmentURL("XDG_CACHE_HOME", request: request) {
            return xdg.appendingPathComponent("huggingface/hub", isDirectory: true)
        }
        return request.homeDirectory.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    private static func absoluteEnvironmentURL(
        _ key: String,
        request: AIModelsAndRuntimesRequest
    ) -> URL? {
        guard let value = request.environment[key], value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }

    private static func applicationInstallations(
        runtimeID: AIModelRuntimeID,
        bundleNames: [String],
        request: AIModelsAndRuntimesRequest
    ) -> [AIModelRuntimeInstallation] {
        var values: [AIModelRuntimeInstallation] = []
        for directory in request.applicationDirectories {
            for bundleName in bundleNames {
                let bundle = directory.appendingPathComponent(bundleName, isDirectory: true)
                guard itemExists(bundle) else { continue }
                values.append(.init(
                    runtimeID: runtimeID,
                    name: bundleName.replacingOccurrences(of: ".app", with: ""),
                    kind: .application,
                    url: bundle,
                    version: bundleVersion(bundle)
                ))
            }
        }
        return uniqueInstallations(values)
    }

    private static func commandInstallations(
        runtimeID: AIModelRuntimeID,
        commandNames: [String],
        extraCandidates: [URL],
        request: AIModelsAndRuntimesRequest
    ) -> [AIModelRuntimeInstallation] {
        let pathDirectories = (request.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        var candidates = extraCandidates
        for directory in pathDirectories {
            candidates.append(contentsOf: commandNames.map { directory.appendingPathComponent($0) })
        }
        var seenTargets: Set<String> = []
        return normalizedURLs(candidates).compactMap { candidate in
            guard itemExists(candidate) else { return nil }
            let target = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard seenTargets.insert(target.path).inserted else { return nil }
            return AIModelRuntimeInstallation(
                runtimeID: runtimeID,
                name: candidate.lastPathComponent,
                kind: .commandLine,
                url: candidate,
                version: nil
            )
        }
    }

    private static func llamaCppInstallations(
        request: AIModelsAndRuntimesRequest
    ) -> [AIModelRuntimeInstallation] {
        var values = commandInstallations(
            runtimeID: .llamaCpp,
            commandNames: ["llama-cli"],
            extraCandidates: request.homebrewPrefixes.map { $0.appendingPathComponent("bin/llama-cli") },
            request: request
        ).map { installation in
            let target = installation.url.resolvingSymlinksInPath().standardizedFileURL
            let components = target.pathComponents
            let cellarIndex = components.firstIndex(of: "Cellar")
            let root: URL
            if let cellarIndex, components.count > cellarIndex + 2 {
                root = URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(cellarIndex + 3))))
            } else {
                root = target
            }
            return AIModelRuntimeInstallation(
                runtimeID: .llamaCpp,
                name: "llama.cpp CLI",
                kind: cellarIndex == nil ? .commandLine : .homebrew,
                url: root,
                version: cellarIndex.map { components[$0 + 2] }
            )
        }

        let sourceRoots = normalizedURLs(
            [request.homeDirectory.appendingPathComponent("llama.cpp", isDirectory: true)]
                + request.additionalModelRoots
        )
        for root in sourceRoots {
            let candidates = [
                root.appendingPathComponent("build/bin/llama-cli"),
                root.appendingPathComponent("bin/llama-cli")
            ]
            guard itemExists(root.appendingPathComponent("CMakeLists.txt")),
                  let command = candidates.first(where: itemExists) else { continue }
            values.append(.init(
                runtimeID: .llamaCpp,
                name: "llama.cpp source build",
                kind: .sourceBuild,
                url: command.deletingLastPathComponent(),
                version: nil
            ))
        }
        return uniqueInstallations(values)
    }

    private static func bundleVersion(_ bundle: URL) -> String? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist), data.count <= 1_048_576,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let values = object as? [String: Any] else { return nil }
        return values["CFBundleShortVersionString"] as? String
    }

    private static func itemExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func normalizedURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }

    private static func normalizedRoots(_ roots: [AIModelRootDescriptor]) -> [AIModelRootDescriptor] {
        var seen: Set<String> = []
        return roots.filter { seen.insert($0.id).inserted }
    }

    private static func uniqueInstallations(
        _ values: [AIModelRuntimeInstallation]
    ) -> [AIModelRuntimeInstallation] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
            .sorted { $0.url.path < $1.url.path }
    }
}
