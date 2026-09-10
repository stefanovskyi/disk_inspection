import Foundation

protocol AICodingInstallationsDetecting: Sendable {
    func detect(
        request: AICodingToolsRequest
    ) async throws -> [AICodingToolID: [AICodingToolInstallation]]
}

struct AICodingInstallationsDetector: AICodingInstallationsDetecting, Sendable {
    private static let maximumManifestSize: UInt64 = 1_048_576
    private static let maximumDirectoryEntries = 2_048
    private static let maximumSymlinkHops = 12

    func detect(
        request: AICodingToolsRequest
    ) async throws -> [AICodingToolID: [AICodingToolInstallation]] {
        let worker = Task.detached(priority: .utility) {
            try Self.detectSynchronously(request: request)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func detectSynchronously(
        request: AICodingToolsRequest
    ) throws -> [AICodingToolID: [AICodingToolInstallation]] {
        let definitions = AICodingToolsCatalog.installationDefinitions(for: request)
        let pathDirectories = Set(
            (request.environment["PATH"] ?? "")
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0), isDirectory: true).standardizedFileURL.path }
        )
        var observations: [AICodingToolInstallation] = []

        for definition in definitions {
            try Task.checkCancellation()
            observations.append(contentsOf: try detectApplications(
                definition: definition,
                request: request,
                pathDirectories: pathDirectories
            ))
            observations.append(contentsOf: try detectStandaloneCLIs(
                definition: definition,
                pathDirectories: pathDirectories
            ))
            observations.append(contentsOf: try detectJavaScriptPackages(
                definition: definition,
                request: request,
                pathDirectories: pathDirectories
            ))
        }

        for definition in definitions {
            try Task.checkCancellation()
            observations.append(contentsOf: try detectHomebrew(
                definition: definition,
                request: request,
                existing: observations,
                pathDirectories: pathDirectories
            ))
        }

        let merged = merge(observations)
        return Dictionary(grouping: merged, by: \.toolID).mapValues { installations in
            installations.sorted(by: installationOrder)
        }
    }

    private static func detectApplications(
        definition: AICodingInstallationDefinition,
        request: AICodingToolsRequest,
        pathDirectories: Set<String>
    ) throws -> [AICodingToolInstallation] {
        var installations: [AICodingToolInstallation] = []
        for directory in request.applicationDirectories {
            try Task.checkCancellation()
            for bundleURL in directoryChildren(directory).filter({
                $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame
            }) {
                try Task.checkCancellation()
                let manifestURL = bundleURL.appendingPathComponent("Contents/Info.plist")
                guard let manifest = propertyList(at: manifestURL) else { continue }
                let bundleIdentifier = manifest["CFBundleIdentifier"] as? String
                let exactRule = definition.applications.first { rule in
                    bundleIdentifier.map(rule.bundleIdentifiers.contains) == true
                }
                let fallbackRule = definition.applications.first { rule in
                    rule.fallbackBundleNames.contains(bundleURL.lastPathComponent)
                }
                guard let rule = exactRule ?? fallbackRule else { continue }

                let source = AICodingInstallationEvidenceSource(.appManifest, url: manifestURL)
                let version = nonemptyString(manifest["CFBundleShortVersionString"]).map {
                    AICodingInstallationFact(value: $0, source: source, confidence: .authoritative)
                }
                let build = nonemptyString(manifest["CFBundleVersion"]).map {
                    AICodingInstallationFact(value: $0, source: source, confidence: .authoritative)
                }
                let appStoreReceipt = bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt")
                let method: AICodingInstallationFact<AICodingInstallMethod>? = itemExists(appStoreReceipt)
                    ? AICodingInstallationFact(
                        value: .appStore,
                        source: .init(.appStoreReceipt, url: appStoreReceipt),
                        confidence: .authoritative
                    )
                    : nil
                let components = rule.bundledComponents.compactMap {
                    componentRule -> AICodingInstallationComponent? in
                    let componentURL = bundleURL.appendingPathComponent(componentRule.relativePath)
                    guard itemExists(componentURL) else { return nil }
                    return AICodingInstallationComponent(
                        name: componentRule.name,
                        url: componentURL,
                        version: nil
                    )
                }
                var notes: [String] = []
                if exactRule == nil {
                    notes.append("Matched by application name; bundle identity was not recognized.")
                }
                installations.append(AICodingToolInstallation(
                    toolID: definition.toolID,
                    surface: .nativeApplication,
                    displayName: rule.displayName,
                    rootURL: bundleURL,
                    entryPoints: bundledApplicationEntryPoints(
                        rule: rule,
                        bundleURL: bundleURL,
                        pathDirectories: pathDirectories
                    ),
                    version: version,
                    build: build,
                    installMethod: method,
                    observedFileDate: observedDate(at: manifestURL),
                    components: components,
                    notes: notes
                ))
            }
        }
        return installations
    }

    private static func bundledApplicationEntryPoints(
        rule: AICodingApplicationInstallationRule,
        bundleURL: URL,
        pathDirectories: Set<String>
    ) -> [AICodingInstallationEntryPoint] {
        let commandNames = Set(rule.bundledComponents.flatMap(\.commandNames))
        var entries: [AICodingInstallationEntryPoint] = []
        for directoryPath in pathDirectories {
            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            for command in commandNames {
                let candidate = directory.appendingPathComponent(command)
                guard itemExists(candidate),
                      let target = resolveLink(candidate),
                      contains(bundleURL, target) else { continue }
                entries.append(AICodingInstallationEntryPoint(
                    name: command,
                    url: candidate,
                    isOnProcessPath: true
                ))
            }
        }
        return entries
    }

    private static func detectStandaloneCLIs(
        definition: AICodingInstallationDefinition,
        pathDirectories: Set<String>
    ) throws -> [AICodingToolInstallation] {
        var installations: [AICodingToolInstallation] = []
        for rule in definition.standaloneCLIs {
            try Task.checkCancellation()
            var candidates: [(entryPoint: URL, target: URL)] = []
            for entryPoint in rule.entryPoints where itemExists(entryPoint) {
                let target = resolveLink(entryPoint) ?? entryPoint.standardizedFileURL
                if let root = rule.owningRoot,
                   !contains(root, target),
                   target.standardizedFileURL != root.standardizedFileURL {
                    continue
                }
                if rule.owningRoot == nil, looksManagedExternally(target) { continue }
                candidates.append((entryPoint, target))
            }
            guard !candidates.isEmpty else { continue }

            let groups = Dictionary(grouping: candidates) { candidate in
                (rule.owningRoot ?? candidate.target).standardizedFileURL.path
            }
            for groupedCandidates in groups.values {
                guard let activeTarget = groupedCandidates.first?.target else { continue }
                let owner = rule.owningRoot ?? activeTarget
                let versionString = standaloneVersion(
                    target: activeTarget,
                    strategy: rule.versionStrategy
                )
                let version = versionString.map {
                    AICodingInstallationFact(
                        value: $0,
                        source: .init(.versionedRelease, url: activeTarget),
                        confidence: .strong
                    )
                }
                let entryPoints = groupedCandidates.map { candidate in
                    AICodingInstallationEntryPoint(
                        name: candidate.entryPoint.lastPathComponent,
                        url: candidate.entryPoint,
                        isOnProcessPath: pathDirectories.contains(
                            candidate.entryPoint.deletingLastPathComponent().standardizedFileURL.path
                        )
                    )
                }
                let methodSource = groupedCandidates.first?.entryPoint ?? owner
                let method = AICodingInstallationFact(
                    value: rule.installMethod,
                    source: AICodingInstallationEvidenceSource(.commandLink, url: methodSource),
                    confidence: .strong
                )
                installations.append(AICodingToolInstallation(
                    toolID: definition.toolID,
                    surface: .commandLine,
                    displayName: rule.displayName,
                    rootURL: owner,
                    entryPoints: entryPoints,
                    version: version,
                    installMethod: method,
                    observedFileDate: observedDate(at: activeTarget),
                    retainedReleases: retainedReleases(
                        in: rule.releasesDirectory,
                        activeTarget: activeTarget,
                        activeVersion: versionString
                    )
                ))
            }
        }
        return installations
    }

    private static func detectJavaScriptPackages(
        definition: AICodingInstallationDefinition,
        request: AICodingToolsRequest,
        pathDirectories: Set<String>
    ) throws -> [AICodingToolInstallation] {
        let roots = javaScriptNodeModulesRoots(request: request)
        var installations: [AICodingToolInstallation] = []
        for rule in definition.javaScriptPackages {
            try Task.checkCancellation()
            let candidates = roots + rule.additionalNodeModulesRoots.map { ($0, .npm) }
            for (nodeModules, method) in candidates {
                try Task.checkCancellation()
                let packageRoot = rule.packageName
                    .split(separator: "/")
                    .reduce(nodeModules) { $0.appendingPathComponent(String($1)) }
                let manifestURL = packageRoot.appendingPathComponent("package.json")
                guard let manifest = jsonDictionary(at: manifestURL),
                      nonemptyString(manifest["name"]) == rule.packageName else { continue }
                let source = AICodingInstallationEvidenceSource(.packageManifest, url: manifestURL)
                let version = nonemptyString(manifest["version"]).map {
                    AICodingInstallationFact(value: $0, source: source, confidence: .authoritative)
                }
                let entryPoints = packageEntryPoints(
                    commands: rule.commands,
                    packageRoot: packageRoot,
                    nodeModulesRoot: nodeModules,
                    method: method,
                    request: request,
                    pathDirectories: pathDirectories
                )
                installations.append(AICodingToolInstallation(
                    toolID: definition.toolID,
                    surface: .commandLine,
                    displayName: rule.displayName,
                    rootURL: packageRoot,
                    entryPoints: entryPoints,
                    version: version,
                    installMethod: AICodingInstallationFact(
                        value: method,
                        source: source,
                        confidence: .strong
                    ),
                    observedFileDate: observedDate(at: manifestURL)
                ))
            }
        }
        return installations
    }

    private static func detectHomebrew(
        definition: AICodingInstallationDefinition,
        request: AICodingToolsRequest,
        existing: [AICodingToolInstallation],
        pathDirectories: Set<String>
    ) throws -> [AICodingToolInstallation] {
        var installations: [AICodingToolInstallation] = []
        for prefix in request.homebrewPrefixes {
            for rule in definition.homebrew {
                try Task.checkCancellation()
                switch rule.kind {
                case .homebrewFormula:
                    guard let installation = homebrewFormula(
                        definition: definition,
                        rule: rule,
                        prefix: prefix,
                        pathDirectories: pathDirectories
                    ) else { continue }
                    installations.append(installation)
                case .homebrewCask:
                    guard let installation = homebrewCask(
                        definition: definition,
                        rule: rule,
                        prefix: prefix,
                        existing: existing,
                        pathDirectories: pathDirectories
                    ) else { continue }
                    installations.append(installation)
                default:
                    continue
                }
            }
        }
        return installations
    }

    private static func homebrewFormula(
        definition: AICodingInstallationDefinition,
        rule: AICodingHomebrewRule,
        prefix: URL,
        pathDirectories: Set<String>
    ) -> AICodingToolInstallation? {
        let formulaRoot = prefix.appendingPathComponent("Cellar/\(rule.token)")
        let releases = directoryChildren(formulaRoot).filter { isDirectory($0) }
        guard !releases.isEmpty else { return nil }
        let optLink = prefix.appendingPathComponent("opt/\(rule.token)")
        let activeRoot = itemExists(optLink)
            ? (resolveLink(optLink) ?? optLink)
            : releases.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }.first!
        let receiptURL = activeRoot.appendingPathComponent("INSTALL_RECEIPT.json")
        guard let receipt = jsonDictionary(at: receiptURL) else { return nil }
        let source = AICodingInstallationEvidenceSource(.homebrewReceipt, url: receiptURL)
        let versionString = activeRoot.lastPathComponent
        let version = AICodingInstallationFact(
            value: versionString,
            source: source,
            confidence: .authoritative
        )
        let entries = rule.commands.compactMap { command -> AICodingInstallationEntryPoint? in
            let url = prefix.appendingPathComponent("bin/\(command)")
            guard itemExists(url) else { return nil }
            return AICodingInstallationEntryPoint(
                name: command,
                url: url,
                isOnProcessPath: pathDirectories.contains(url.deletingLastPathComponent().path)
            )
        }
        let retained = releases.map { release in
            AICodingRetainedRelease(
                version: release.lastPathComponent,
                url: release,
                isActive: contains(release, activeRoot) || contains(activeRoot, release)
            )
        }
        return AICodingToolInstallation(
            toolID: definition.toolID,
            surface: rule.surface,
            displayName: rule.displayName,
            rootURL: formulaRoot,
            entryPoints: entries,
            version: version,
            installMethod: AICodingInstallationFact(
                value: .homebrewFormula,
                source: source,
                confidence: .authoritative
            ),
            installedOrUpdatedAt: receiptDate(receipt, source: source),
            observedFileDate: observedDate(at: receiptURL),
            retainedReleases: retained
        )
    }

    private static func homebrewCask(
        definition: AICodingInstallationDefinition,
        rule: AICodingHomebrewRule,
        prefix: URL,
        existing: [AICodingToolInstallation],
        pathDirectories: Set<String>
    ) -> AICodingToolInstallation? {
        let caskRoot = prefix.appendingPathComponent("Caskroom/\(rule.token)")
        guard isDirectory(caskRoot),
              let receiptURL = shallowFile(named: "INSTALL_RECEIPT.json", below: caskRoot, depth: 4),
              let receipt = jsonDictionary(at: receiptURL) else { return nil }
        let source = AICodingInstallationEvidenceSource(.homebrewReceipt, url: receiptURL)
        let application = existing.first {
            $0.toolID == definition.toolID
                && $0.surface == .nativeApplication
                && ($0.displayName == rule.displayName
                    || definition.applications.count == 1)
        }
        let root = application?.rootURL ?? caskRoot
        let version = application?.version ?? receiptVersion(receipt).map {
            AICodingInstallationFact(value: $0, source: source, confidence: .authoritative)
        }
        let entries = rule.commands.compactMap { command -> AICodingInstallationEntryPoint? in
            let url = prefix.appendingPathComponent("bin/\(command)")
            guard itemExists(url) else { return nil }
            return AICodingInstallationEntryPoint(
                name: command,
                url: url,
                isOnProcessPath: pathDirectories.contains(url.deletingLastPathComponent().path)
            )
        }
        return AICodingToolInstallation(
            toolID: definition.toolID,
            surface: rule.surface,
            displayName: application?.displayName ?? rule.displayName,
            rootURL: root,
            entryPoints: entries,
            version: version,
            build: application?.build,
            installMethod: AICodingInstallationFact(
                value: .homebrewCask,
                source: source,
                confidence: .authoritative
            ),
            installedOrUpdatedAt: receiptDate(receipt, source: source),
            observedFileDate: application?.observedFileDate ?? observedDate(at: receiptURL),
            components: application?.components ?? [],
            notes: application?.notes ?? []
        )
    }

    private static func merge(
        _ observations: [AICodingToolInstallation]
    ) -> [AICodingToolInstallation] {
        var byID: [String: AICodingToolInstallation] = [:]
        for observation in observations {
            guard let current = byID[observation.id] else {
                byID[observation.id] = observation
                continue
            }
            var notes = current.notes + observation.notes
            noteConflict(current.version, observation.version, field: "version", notes: &notes)
            noteConflict(current.build, observation.build, field: "build", notes: &notes)
            noteConflict(
                current.installMethod,
                observation.installMethod,
                field: "installation method",
                notes: &notes
            )
            byID[observation.id] = AICodingToolInstallation(
                toolID: current.toolID,
                surface: current.surface,
                displayName: current.displayName,
                rootURL: current.rootURL,
                entryPoints: current.entryPoints + observation.entryPoints,
                version: preferred(current.version, observation.version),
                build: preferred(current.build, observation.build),
                installMethod: preferred(current.installMethod, observation.installMethod),
                installedOrUpdatedAt: preferred(
                    current.installedOrUpdatedAt,
                    observation.installedOrUpdatedAt
                ),
                observedFileDate: preferred(current.observedFileDate, observation.observedFileDate),
                components: current.components + observation.components,
                retainedReleases: current.retainedReleases + observation.retainedReleases,
                notes: notes
            )
        }
        return Array(byID.values)
    }

    private static func preferred<Value>(
        _ left: AICodingInstallationFact<Value>?,
        _ right: AICodingInstallationFact<Value>?
    ) -> AICodingInstallationFact<Value>? where Value: Equatable & Sendable {
        guard let left else { return right }
        guard let right else { return left }
        if left.confidence != right.confidence {
            return left.confidence > right.confidence ? left : right
        }
        return evidencePriority(left.source.kind) <= evidencePriority(right.source.kind)
            ? left
            : right
    }

    private static func noteConflict<Value>(
        _ left: AICodingInstallationFact<Value>?,
        _ right: AICodingInstallationFact<Value>?,
        field: String,
        notes: inout [String]
    ) where Value: Equatable & Sendable {
        guard let left, let right,
              left.value != right.value,
              left.confidence == .authoritative,
              right.confidence == .authoritative else { return }
        notes.append("Conflicting authoritative \(field) metadata was found.")
    }

    private static func evidencePriority(_ kind: AICodingInstallationEvidenceKind) -> Int {
        switch kind {
        case .homebrewReceipt: 0
        case .appManifest: 1
        case .packageManifest: 2
        case .versionedRelease: 3
        case .appStoreReceipt: 4
        case .commandLink: 5
        case .bundledComponent: 6
        case .fileMetadata: 7
        }
    }

    private static func installationOrder(
        _ left: AICodingToolInstallation,
        _ right: AICodingToolInstallation
    ) -> Bool {
        if left.surface != right.surface {
            return left.surface == .nativeApplication
        }
        if left.displayName != right.displayName {
            return left.displayName < right.displayName
        }
        return left.rootURL.path < right.rootURL.path
    }

    private static func javaScriptNodeModulesRoots(
        request: AICodingToolsRequest
    ) -> [(URL, AICodingInstallMethod)] {
        let home = request.homeDirectory
        var roots: [(URL, AICodingInstallMethod)] = [
            (home.appendingPathComponent(".npm-global/lib/node_modules"), .npm),
            (home.appendingPathComponent(".bun/install/global/node_modules"), .bun),
            (home.appendingPathComponent(".config/yarn/global/node_modules"), .yarn),
            (home.appendingPathComponent(".yarn/global/node_modules"), .yarn)
        ]
        for prefix in request.homebrewPrefixes {
            roots.append((prefix.appendingPathComponent("lib/node_modules"), .npm))
        }
        let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
        roots.append(contentsOf: directoryChildren(nvmVersions).map {
            ($0.appendingPathComponent("lib/node_modules"), .npm)
        })
        for pnpmRoot in [
            home.appendingPathComponent(".local/share/pnpm/global"),
            home.appendingPathComponent("Library/pnpm/global")
        ] {
            roots.append(contentsOf: directoryChildren(pnpmRoot).map {
                ($0.appendingPathComponent("node_modules"), .pnpm)
            })
        }
        var seen: Set<String> = []
        return roots.filter { seen.insert($0.0.standardizedFileURL.path).inserted }
    }

    private static func packageEntryPoints(
        commands: [String],
        packageRoot: URL,
        nodeModulesRoot: URL,
        method: AICodingInstallMethod,
        request: AICodingToolsRequest,
        pathDirectories: Set<String>
    ) -> [AICodingInstallationEntryPoint] {
        var candidateDirectories: [URL] = []
        switch method {
        case .bun:
            candidateDirectories.append(request.homeDirectory.appendingPathComponent(".bun/bin"))
        case .yarn:
            candidateDirectories.append(request.homeDirectory.appendingPathComponent(".yarn/bin"))
        case .pnpm:
            candidateDirectories.append(request.homeDirectory.appendingPathComponent(".local/share/pnpm"))
            candidateDirectories.append(request.homeDirectory.appendingPathComponent("Library/pnpm"))
        default:
            if nodeModulesRoot.lastPathComponent == "node_modules",
               nodeModulesRoot.deletingLastPathComponent().lastPathComponent == "lib" {
                candidateDirectories.append(
                    nodeModulesRoot.deletingLastPathComponent().deletingLastPathComponent()
                        .appendingPathComponent("bin")
                )
            }
        }
        candidateDirectories.append(contentsOf: pathDirectories.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        })

        var entries: [AICodingInstallationEntryPoint] = []
        for directory in candidateDirectories {
            for command in commands {
                let candidate = directory.appendingPathComponent(command)
                guard itemExists(candidate),
                      let target = resolveLink(candidate),
                      contains(packageRoot, target) else { continue }
                entries.append(AICodingInstallationEntryPoint(
                    name: command,
                    url: candidate,
                    isOnProcessPath: pathDirectories.contains(directory.standardizedFileURL.path)
                ))
            }
        }
        return entries
    }

    private static func retainedReleases(
        in directory: URL?,
        activeTarget: URL,
        activeVersion: String?
    ) -> [AICodingRetainedRelease] {
        guard let directory else { return [] }
        return directoryChildren(directory).map { release in
            let active = contains(release, activeTarget)
                || release.standardizedFileURL == activeTarget.standardizedFileURL
                || (activeVersion != nil && release.lastPathComponent == activeVersion)
            return AICodingRetainedRelease(
                version: release.lastPathComponent,
                url: release,
                isActive: active
            )
        }
    }

    private static func standaloneVersion(
        target: URL,
        strategy: AICodingStandaloneVersionStrategy
    ) -> String? {
        switch strategy {
        case .targetName:
            return plausibleVersion(target.lastPathComponent)
        case .targetParentName:
            return plausibleVersion(target.deletingLastPathComponent().lastPathComponent)
        case .nearestVersionComponent:
            return target.pathComponents.reversed().compactMap(plausibleVersion).first
        case .none:
            return nil
        }
    }

    private static func plausibleVersion(_ value: String) -> String? {
        guard value.contains(where: \.isNumber),
              value.contains(".") else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.-_+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    private static func receiptDate(
        _ receipt: [String: Any],
        source: AICodingInstallationEvidenceSource
    ) -> AICodingInstallationFact<Date>? {
        let timestamp: TimeInterval?
        if let number = receipt["time"] as? NSNumber {
            timestamp = number.doubleValue
        } else if let string = receipt["time"] as? String {
            timestamp = TimeInterval(string)
        } else {
            timestamp = nil
        }
        guard let timestamp, timestamp > 0 else { return nil }
        return AICodingInstallationFact(
            value: Date(timeIntervalSince1970: timestamp),
            source: source,
            confidence: .authoritative
        )
    }

    private static func receiptVersion(_ value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let version = nonemptyString(dictionary["version"]) { return version }
            for nested in dictionary.values {
                if let version = receiptVersion(nested) { return version }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let version = receiptVersion(nested) { return version }
            }
        }
        return nil
    }

    private static func observedDate(
        at url: URL
    ) -> AICodingInstallationFact<Date>? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let date = [
            attributes[.creationDate] as? Date,
            attributes[.modificationDate] as? Date
        ]
        .compactMap { $0 }
        .max()
        guard let date else { return nil }
        return AICodingInstallationFact(
            value: date,
            source: .init(.fileMetadata, url: url),
            confidence: .heuristic
        )
    }

    private static func propertyList(at url: URL) -> [String: Any]? {
        guard let data = boundedData(at: url),
              let value = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) else { return nil }
        return value as? [String: Any]
    }

    private static func jsonDictionary(at url: URL) -> [String: Any]? {
        guard let data = boundedData(at: url),
              let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return value as? [String: Any]
    }

    private static func boundedData(at url: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size <= maximumManifestSize else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func directoryChildren(_ directory: URL) -> [URL] {
        guard let values = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return [] }
        return Array(values.prefix(maximumDirectoryEntries))
    }

    private static func shallowFile(
        named name: String,
        below root: URL,
        depth: Int
    ) -> URL? {
        var queue: [(URL, Int)] = [(root, 0)]
        var examined = 0
        while !queue.isEmpty, examined < maximumDirectoryEntries {
            let (directory, level) = queue.removeFirst()
            for child in directoryChildren(directory) {
                examined += 1
                if child.lastPathComponent == name { return child }
                guard level < depth,
                      isDirectory(child),
                      !isSymbolicLink(child) else { continue }
                queue.append((child, level + 1))
            }
        }
        return nil
    }

    private static func resolveLink(_ source: URL) -> URL? {
        var current = source.standardizedFileURL
        var visited: Set<String> = []
        for _ in 0..<maximumSymlinkHops {
            guard visited.insert(current.path).inserted else { return nil }
            guard isSymbolicLink(current) else { return current }
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: current.path
            ) else { return nil }
            if destination.hasPrefix("/") {
                current = URL(fileURLWithPath: destination).standardizedFileURL
            } else {
                current = current.deletingLastPathComponent()
                    .appendingPathComponent(destination)
                    .standardizedFileURL
            }
        }
        return nil
    }

    private static func itemExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var value: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &value)
            && value.boolValue
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        return childPath == parentPath
            || childPath.hasPrefix(parentPath == "/" ? "/" : parentPath + "/")
    }

    private static func looksManagedExternally(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/node_modules/")
            || path.contains("/Cellar/")
            || path.contains("/Caskroom/")
            || path.contains(".app/Contents/")
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }
}
