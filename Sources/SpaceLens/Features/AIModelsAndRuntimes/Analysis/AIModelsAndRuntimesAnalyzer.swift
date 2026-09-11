import Foundation

protocol AIModelsAndRuntimesAnalyzing: Sendable {
    func analyze(
        request: AIModelsAndRuntimesRequest,
        onProgress: @escaping @Sendable (AIModelsProgress) -> Void
    ) async throws -> AIModelsAndRuntimesReport
}

struct AIModelsAndRuntimesAnalyzer: AIModelsAndRuntimesAnalyzing, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (AIModelsProgress) -> Void

    private let scanner: DiskScanner
    private let fixedDiscovery: AIModelsDiscoveryResult?

    init(
        scanner: DiskScanner = DiskScanner(),
        discovery: AIModelsDiscoveryResult? = nil
    ) {
        self.scanner = scanner
        fixedDiscovery = discovery
    }

    func analyze(
        request: AIModelsAndRuntimesRequest,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> AIModelsAndRuntimesReport {
        let startedAt = Date()
        let discovery = fixedDiscovery ?? AIModelsDiscovery.discover(request: request)
        let accumulator = AIModelsObservationAccumulator()
        var locations: [AIModelStorageLocation] = []
        var completedLocations = 0

        for descriptor in discovery.roots {
            try Task.checkCancellation()
            let runtime = AIModelsCatalog.metadata(for: descriptor.runtimeID)
            onProgress(.init(
                currentRuntime: runtime,
                currentLocationName: descriptor.name,
                currentPath: descriptor.url.path,
                completedLocations: completedLocations,
                totalLocations: discovery.roots.count,
                itemsScanned: accumulator.totalItemCount,
                mappedBytes: accumulator.totalSize
            ))

            let metadata = try? LowLevelMetadataReader.metadata(at: descriptor.url)
            if metadata?.kind == .symbolicLink {
                locations.append(.init(
                    runtimeID: descriptor.runtimeID,
                    name: descriptor.name,
                    url: descriptor.url,
                    size: 0,
                    itemCount: 0,
                    latestModificationDate: metadata?.modificationDate,
                    status: .linked,
                    root: nil
                ))
                completedLocations += 1
                continue
            }

            do {
                let completedBeforeScan = completedLocations
                let result = try await scanner.scan(
                    url: descriptor.url,
                    onItem: { item in
                        accumulator.record(item, descriptor: descriptor)
                    },
                    onProgress: { progress in
                        onProgress(.init(
                            currentRuntime: runtime,
                            currentLocationName: descriptor.name,
                            currentPath: progress.currentPath,
                            completedLocations: completedBeforeScan,
                            totalLocations: discovery.roots.count,
                            itemsScanned: accumulator.totalItemCount,
                            mappedBytes: accumulator.totalSize
                        ))
                    }
                )
                let metrics = accumulator.metrics(for: descriptor.id)
                let status: AIModelLocationStatus
                if result.diagnostics.providerTimeouts > 0 {
                    status = .stalled
                } else if result.unreadableItems > 0 {
                    status = .unreadable
                } else {
                    status = .measured
                }
                locations.append(.init(
                    runtimeID: descriptor.runtimeID,
                    name: descriptor.name,
                    url: descriptor.url,
                    size: metrics.size,
                    itemCount: metrics.itemCount,
                    latestModificationDate: metrics.latestModificationDate,
                    status: status,
                    root: result.root
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch ScanFailure.cancelled {
                throw CancellationError()
            } catch {
                locations.append(.init(
                    runtimeID: descriptor.runtimeID,
                    name: descriptor.name,
                    url: descriptor.url,
                    size: 0,
                    itemCount: 0,
                    latestModificationDate: nil,
                    status: .unreadable,
                    root: nil
                ))
            }

            completedLocations += 1
            onProgress(.init(
                currentRuntime: runtime,
                currentLocationName: descriptor.name,
                currentPath: descriptor.url.path,
                completedLocations: completedLocations,
                totalLocations: discovery.roots.count,
                itemsScanned: accumulator.totalItemCount,
                mappedBytes: accumulator.totalSize
            ))
        }

        try Task.checkCancellation()
        let snapshot = accumulator.snapshot()
        var models = Self.models(discovery: discovery, snapshot: snapshot)
        models = Self.annotatingDuplicates(models)

        let standaloneModels = models.filter { $0.runtimeID == .standalone }
        let standaloneLocations = Self.standaloneLocations(
            descriptors: discovery.roots.filter { $0.runtimeID == .standalone },
            scannedLocations: locations.filter { $0.runtimeID == .standalone },
            models: standaloneModels
        )
        locations.removeAll { $0.runtimeID == .standalone }
        locations.append(contentsOf: standaloneLocations)

        let runtimes = AIModelsCatalog.supportedRuntimes.map { metadata in
            let runtimeLocations = locations.filter { $0.runtimeID == metadata.id }
                .sorted { left, right in
                    if left.size == right.size { return left.url.path < right.url.path }
                    return left.size > right.size
                }
            let categories: [AIModelCategoryBreakdown]
            if metadata.id == .standalone {
                let size = standaloneModels.reduce(Int64(0)) { safeMetricAdd($0, $1.allocatedSize) }
                categories = size > 0
                    ? [.init(category: .weights, size: size, itemCount: standaloneModels.count)]
                    : []
            } else {
                categories = snapshot.categoryMetrics[metadata.id, default: [:]]
                    .map { .init(category: $0.key, size: $0.value.size, itemCount: $0.value.itemCount) }
                    .filter { $0.size > 0 || $0.itemCount > 0 }
                    .sorted { $0.size > $1.size }
            }
            return AIModelRuntimeReport(
                runtime: metadata,
                models: models.filter { $0.runtimeID == metadata.id }
                    .sorted { left, right in
                        if left.allocatedSize == right.allocatedSize {
                            return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
                        }
                        return left.allocatedSize > right.allocatedSize
                    },
                installations: discovery.installations[metadata.id, default: []],
                locations: runtimeLocations,
                categories: categories
            )
        }
        return AIModelsAndRuntimesReport(runtimes: runtimes, startedAt: startedAt)
    }

    private static func models(
        discovery: AIModelsDiscoveryResult,
        snapshot: AIModelsObservationSnapshot
    ) -> [AIModelRecord] {
        var values: [AIModelRecord] = []
        values.append(contentsOf: ollamaModels(discovery: discovery, snapshot: snapshot))
        values.append(contentsOf: lmStudioModels(discovery: discovery, snapshot: snapshot))
        values.append(contentsOf: huggingFaceModels(snapshot: snapshot))
        values.append(contentsOf: standaloneModels(discovery: discovery, snapshot: snapshot))
        var seen: Set<String> = []
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func ollamaModels(
        discovery: AIModelsDiscoveryResult,
        snapshot: AIModelsObservationSnapshot
    ) -> [AIModelRecord] {
        let descriptors = discovery.roots.filter { $0.runtimeID == .ollama && $0.modelRoot != nil }
        var pending: [(url: URL, name: String, manifest: AIModelInventoryParsers.OllamaManifest,
                       blobItems: [String: ScannedFileItem], modelRoot: URL)] = []
        var digestReferences: [String: Int] = [:]

        for descriptor in descriptors {
            guard let modelRoot = descriptor.modelRoot else { continue }
            let candidates = snapshot.candidates[descriptor.id, default: []]
            let blobRoot = modelRoot.appendingPathComponent("blobs", isDirectory: true)
            let manifestRoot = modelRoot.appendingPathComponent("manifests", isDirectory: true)
            var blobItems: [String: ScannedFileItem] = [:]
            for item in candidates where AIModelsDiscovery.contains(blobRoot, item.url) {
                blobItems[item.url.standardizedFileURL.path] = item
            }
            for item in candidates where AIModelsDiscovery.contains(manifestRoot, item.url) {
                guard item.kind == .regular,
                      let manifest = AIModelInventoryParsers.ollamaManifest(at: item.url) else { continue }
                let components = relativeComponents(from: manifestRoot, to: item.url)
                guard components.count >= 2 else { continue }
                let name = components.suffix(2).joined(separator: ":")
                let digests = ([manifest.config].compactMap { $0 } + manifest.layers)
                    .compactMap { AIModelInventoryParsers.normalizedSHA256($0.digest) }
                for digest in Set(digests) { digestReferences[digest, default: 0] += 1 }
                pending.append((item.url, name, manifest, blobItems, modelRoot))
            }
        }

        return pending.map { entry in
            let descriptors = ([entry.manifest.config].compactMap { $0 } + entry.manifest.layers)
            var size: Int64 = 0
            var shared: Int64 = 0
            var contentDigests: [String] = []
            var latest: Date?
            var modelBlob: URL?
            var metadata: GGUFMetadata?

            for descriptor in descriptors {
                guard let digest = AIModelInventoryParsers.normalizedSHA256(descriptor.digest) else { continue }
                let blob = entry.modelRoot.appendingPathComponent("blobs/sha256-\(digest)")
                guard AIModelsDiscovery.contains(
                    entry.modelRoot.appendingPathComponent("blobs", isDirectory: true), blob
                ) else { continue }
                let item = entry.blobItems[blob.standardizedFileURL.path]
                let bytes = item?.size ?? max(descriptor.size, 0)
                size = safeMetricAdd(size, bytes)
                if digestReferences[digest, default: 0] > 1 { shared = safeMetricAdd(shared, bytes) }
                latest = latestDate(latest, item?.modificationDate)
                if descriptor.mediaType.contains(".model") {
                    contentDigests.append(digest)
                    if modelBlob == nil {
                        modelBlob = blob
                        metadata = AIModelInventoryParsers.ggufMetadata(at: blob)
                    }
                }
            }
            let firstModelDigest = entry.manifest.layers.first(where: { $0.mediaType.contains(".model") })
                .flatMap { AIModelInventoryParsers.normalizedSHA256($0.digest) }
            return AIModelRecord(
                id: "ollama|\(entry.url.standardizedFileURL.path)",
                runtimeID: .ollama,
                displayName: entry.name,
                format: modelBlob == nil ? .unknown : .gguf,
                quantization: metadata?.quantization,
                allocatedSize: size,
                sharedBytes: shared,
                primaryURL: entry.url,
                latestModificationDate: latest,
                digest: firstModelDigest,
                contentDigests: contentDigests
            )
        }
    }

    private static func lmStudioModels(
        discovery: AIModelsDiscoveryResult,
        snapshot: AIModelsObservationSnapshot
    ) -> [AIModelRecord] {
        let descriptors = discovery.roots.filter { $0.runtimeID == .lmStudio && $0.modelRoot != nil }
        var values: [AIModelRecord] = []
        for descriptor in descriptors {
            guard let modelRoot = descriptor.modelRoot else { continue }
            let items = snapshot.candidates[descriptor.id, default: []].filter {
                AIModelsDiscovery.contains(modelRoot, $0.url) && $0.kind == .regular
            }
            for item in items where item.url.pathExtension.lowercased() == "gguf" {
                guard let metadata = AIModelInventoryParsers.ggufMetadata(at: item.url) else { continue }
                values.append(.init(
                    id: "lm-studio|\(item.url.standardizedFileURL.path)",
                    runtimeID: .lmStudio,
                    displayName: metadata.name ?? item.url.deletingPathExtension().lastPathComponent,
                    format: .gguf,
                    quantization: metadata.quantization
                        ?? AIModelInventoryParsers.quantizationFromFilename(item.url.lastPathComponent),
                    allocatedSize: item.size,
                    primaryURL: item.url,
                    latestModificationDate: item.modificationDate
                ))
            }

            let safeTensorItems = items.filter { $0.url.pathExtension.lowercased() == "safetensors" }
            let groups = Dictionary(grouping: safeTensorItems, by: { $0.url.deletingLastPathComponent().path })
            for (directoryPath, shards) in groups {
                let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
                let configuration = directory.appendingPathComponent("config.json")
                guard FileManager.default.fileExists(atPath: configuration.path),
                      shards.contains(where: { AIModelInventoryParsers.isSafeTensors(at: $0.url) }) else {
                    continue
                }
                let config = AIModelInventoryParsers.jsonObject(at: configuration)
                let quantization = mlxQuantization(config)
                let relative = relativeComponents(from: modelRoot, to: directory)
                values.append(.init(
                    id: "lm-studio|\(directory.standardizedFileURL.path)",
                    runtimeID: .lmStudio,
                    displayName: relative.isEmpty ? directory.lastPathComponent : relative.joined(separator: "/"),
                    format: .mlx,
                    quantization: quantization,
                    allocatedSize: shards.reduce(0) { safeMetricAdd($0, $1.size) },
                    primaryURL: directory,
                    latestModificationDate: shards.compactMap(\.modificationDate).max()
                ))
            }
        }
        return values
    }

    private static func huggingFaceModels(
        snapshot: AIModelsObservationSnapshot
    ) -> [AIModelRecord] {
        snapshot.huggingFaceRepos.map { repoPath, observation in
            let url = URL(fileURLWithPath: repoPath, isDirectory: true)
            let encodedName = url.lastPathComponent
            let displayName = encodedName.hasPrefix("models--")
                ? String(encodedName.dropFirst("models--".count)).replacingOccurrences(of: "--", with: "/")
                : encodedName
            let format: AIModelFormat
            if observation.extensions.contains("gguf") {
                format = .gguf
            } else if observation.extensions.contains("safetensors") {
                format = .safetensors
            } else {
                format = .unknown
            }
            return AIModelRecord(
                id: "hugging-face|\(repoPath)",
                runtimeID: .huggingFace,
                displayName: displayName,
                format: format,
                quantization: observation.quantizations.sorted().first,
                allocatedSize: observation.metrics.size,
                primaryURL: url,
                latestModificationDate: observation.metrics.latestModificationDate,
                contentDigests: Array(observation.largeDigests)
            )
        }
    }

    private static func standaloneModels(
        discovery: AIModelsDiscoveryResult,
        snapshot: AIModelsObservationSnapshot
    ) -> [AIModelRecord] {
        let descriptors = discovery.roots.filter { $0.runtimeID == .standalone }
        var values: [AIModelRecord] = []
        for descriptor in descriptors {
            let items = snapshot.candidates[descriptor.id, default: []].filter {
                $0.kind == .regular && descriptor.includes($0.url)
            }
            let ggufs = items.filter { $0.url.pathExtension.lowercased() == "gguf" }
            let ggufGroups = Dictionary(grouping: ggufs, by: { splitGGUFKey($0.url) })
            for (_, parts) in ggufGroups {
                guard let first = parts.sorted(by: { $0.url.path < $1.url.path }).first,
                      let metadata = AIModelInventoryParsers.ggufMetadata(at: first.url) else { continue }
                let primaryURL = parts.count > 1 ? first.url.deletingLastPathComponent() : first.url
                values.append(.init(
                    id: "standalone|\(first.url.standardizedFileURL.path)",
                    runtimeID: .standalone,
                    displayName: metadata.name ?? splitGGUFKey(first.url),
                    format: .gguf,
                    quantization: metadata.quantization
                        ?? AIModelInventoryParsers.quantizationFromFilename(first.url.lastPathComponent),
                    allocatedSize: parts.reduce(0) { safeMetricAdd($0, $1.size) },
                    primaryURL: primaryURL,
                    latestModificationDate: parts.compactMap(\.modificationDate).max()
                ))
            }

            let tensors = items.filter { $0.url.pathExtension.lowercased() == "safetensors" }
            let directories = Dictionary(grouping: tensors, by: { $0.url.deletingLastPathComponent().path })
            for (directoryPath, shards) in directories {
                guard shards.contains(where: { AIModelInventoryParsers.isSafeTensors(at: $0.url) }) else {
                    continue
                }
                let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
                let config = AIModelInventoryParsers.jsonObject(
                    at: directory.appendingPathComponent("config.json")
                )
                let isMLX = config != nil
                values.append(.init(
                    id: "standalone|\(directory.standardizedFileURL.path)",
                    runtimeID: .standalone,
                    displayName: directory.lastPathComponent,
                    format: isMLX ? .mlx : .safetensors,
                    quantization: mlxQuantization(config),
                    allocatedSize: shards.reduce(0) { safeMetricAdd($0, $1.size) },
                    primaryURL: shards.count > 1 || isMLX ? directory : shards[0].url,
                    latestModificationDate: shards.compactMap(\.modificationDate).max()
                ))
            }
        }
        return values
    }

    private static func annotatingDuplicates(_ models: [AIModelRecord]) -> [AIModelRecord] {
        var owners: [String: [(id: String, runtimeID: AIModelRuntimeID, name: String)]] = [:]
        for model in models {
            for digest in model.contentDigests {
                owners[digest, default: []].append((model.id, model.runtimeID, model.displayName))
            }
        }
        return models.map { model in
            var matches: [(AIModelRuntimeID, String)] = []
            for digest in model.contentDigests {
                matches.append(contentsOf: owners[digest, default: []]
                    .filter { $0.id != model.id }
                    .map { ($0.runtimeID, $0.name) })
            }
            var seen: Set<String> = []
            let unique = matches.filter { seen.insert("\($0.0.rawValue)|\($0.1)").inserted }
            guard !unique.isEmpty else { return model }
            let labels = unique.prefix(2).map {
                "\(AIModelsCatalog.metadata(for: $0.0).displayName) · \($0.1)"
            }
            let suffix = unique.count > 2 ? " and \(unique.count - 2) more" : ""
            return model.withDuplicateDescription("Same content as " + labels.joined(separator: ", ") + suffix)
        }
    }

    private static func standaloneLocations(
        descriptors: [AIModelRootDescriptor],
        scannedLocations: [AIModelStorageLocation],
        models: [AIModelRecord]
    ) -> [AIModelStorageLocation] {
        descriptors.compactMap { descriptor in
            let matched = models.filter { AIModelsDiscovery.contains(descriptor.url, $0.primaryURL) }
            let scanned = scannedLocations.first { $0.url.standardizedFileURL == descriptor.url }
            guard !matched.isEmpty || scanned?.status.isIssue == true else { return nil }
            return AIModelStorageLocation(
                runtimeID: .standalone,
                name: descriptor.name,
                url: descriptor.url,
                size: matched.reduce(0) { safeMetricAdd($0, $1.allocatedSize) },
                itemCount: matched.count,
                latestModificationDate: matched.compactMap(\.latestModificationDate).max(),
                status: scanned?.status ?? .measured,
                root: scanned?.root
            )
        }
    }

    private static func mlxQuantization(_ config: [String: Any]?) -> String? {
        guard let config else { return nil }
        let quantization = config["quantization"] as? [String: Any]
            ?? config["quantization_config"] as? [String: Any]
        guard let bits = (quantization?["bits"] as? NSNumber)?.intValue else { return nil }
        return "\(bits)-bit MLX"
    }

    private static func splitGGUFKey(_ url: URL) -> String {
        let name = url.lastPathComponent
        let pattern = "-\\d{5}-of-\\d{5}(?=\\.gguf$)"
        let grouped = name.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return (grouped as NSString).deletingPathExtension
    }

    private static func relativeComponents(from root: URL, to child: URL) -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count >= rootComponents.count,
              zip(rootComponents, childComponents).allSatisfy({ $0 == $1 }) else { return [] }
        return Array(childComponents.dropFirst(rootComponents.count))
    }

    private static func latestDate(_ left: Date?, _ right: Date?) -> Date? {
        switch (left, right) {
        case (.none, .none): nil
        case (.some(let value), .none), (.none, .some(let value)): value
        case (.some(let left), .some(let right)): max(left, right)
        }
    }
}

private final class AIModelsObservationAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var globalFileIdentities: Set<FileIdentity> = []
    private var globalFallbackPaths: Set<String> = []
    private var locationMetrics: [String: AIModelsMutableMetrics] = [:]
    private var runtimeMetrics: [AIModelRuntimeID: [AIModelStorageCategory: AIModelsMutableMetrics]] = [:]
    private var candidateItems: [String: [ScannedFileItem]] = [:]
    private var hubRepos: [String: AIModelsHubRepoObservation] = [:]
    private var overall = AIModelsMutableMetrics()

    var totalItemCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return overall.itemCount
    }

    var totalSize: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return overall.size
    }

    func record(_ item: ScannedFileItem, descriptor: AIModelRootDescriptor) {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor.includes(item.url) else { return }

        if shouldRetainCandidate(item, descriptor: descriptor) {
            candidateItems[descriptor.id, default: []].append(item)
        }

        if descriptor.runtimeID == .huggingFace {
            recordHubRepo(item, descriptor: descriptor)
        }

        guard descriptor.purpose != .standaloneSearch else { return }
        let isUnique: Bool
        if item.kind == .regular, let identity = item.identity {
            isUnique = globalFileIdentities.insert(identity).inserted
        } else if item.kind == .regular {
            isUnique = globalFallbackPaths.insert(item.url.standardizedFileURL.path).inserted
        } else {
            isUnique = true
        }
        guard isUnique else { return }

        var location = locationMetrics[descriptor.id] ?? AIModelsMutableMetrics()
        location.record(item)
        locationMetrics[descriptor.id] = location
        overall.record(item)

        let category = category(for: item, descriptor: descriptor)
        var categories = runtimeMetrics[descriptor.runtimeID] ?? [:]
        var metrics = categories[category] ?? AIModelsMutableMetrics()
        metrics.record(item)
        categories[category] = metrics
        runtimeMetrics[descriptor.runtimeID] = categories
    }

    func metrics(for descriptorID: String) -> AIModelsMutableMetrics {
        lock.lock()
        defer { lock.unlock() }
        return locationMetrics[descriptorID] ?? AIModelsMutableMetrics()
    }

    func snapshot() -> AIModelsObservationSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return .init(
            categoryMetrics: runtimeMetrics,
            candidates: candidateItems,
            huggingFaceRepos: hubRepos
        )
    }

    private func shouldRetainCandidate(
        _ item: ScannedFileItem,
        descriptor: AIModelRootDescriptor
    ) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        switch descriptor.runtimeID {
        case .ollama:
            guard let modelRoot = descriptor.modelRoot else { return false }
            return AIModelsDiscovery.contains(modelRoot.appendingPathComponent("blobs"), item.url)
                || AIModelsDiscovery.contains(modelRoot.appendingPathComponent("manifests"), item.url)
        case .lmStudio:
            guard let modelRoot = descriptor.modelRoot,
                  AIModelsDiscovery.contains(modelRoot, item.url) else { return false }
            return ["gguf", "safetensors", "json"].contains(ext)
        case .huggingFace:
            return true
        case .standalone:
            return ["gguf", "ggml", "safetensors"].contains(ext)
        case .llamaCpp:
            return false
        default:
            return false
        }
    }

    private func recordHubRepo(_ item: ScannedFileItem, descriptor: AIModelRootDescriptor) {
        let components = relativeComponents(from: descriptor.url, to: item.url)
        guard let repoName = components.first, repoName.hasPrefix("models--") else { return }
        let repoURL = descriptor.url.appendingPathComponent(repoName, isDirectory: true)
        var observation = hubRepos[repoURL.standardizedFileURL.path] ?? AIModelsHubRepoObservation()
        observation.metrics.record(item)
        let ext = item.url.pathExtension.lowercased()
        if !ext.isEmpty { observation.extensions.insert(ext) }
        if let quantization = AIModelInventoryParsers.quantizationFromFilename(item.url.lastPathComponent) {
            observation.quantizations.insert(quantization)
        }
        let filename = item.url.lastPathComponent.lowercased()
        if item.kind == .regular, item.size >= 1_048_576,
           filename.count == 64, filename.allSatisfy({ $0.isHexDigit }) {
            observation.largeDigests.insert(filename)
        }
        hubRepos[repoURL.standardizedFileURL.path] = observation
    }

    private func category(
        for item: ScannedFileItem,
        descriptor: AIModelRootDescriptor
    ) -> AIModelStorageCategory {
        if descriptor.purpose == .installation { return .runtimes }
        let components = relativeComponents(from: descriptor.url, to: item.url).map { $0.lowercased() }
        let path = components.joined(separator: "/")
        let ext = item.url.pathExtension.lowercased()
        switch descriptor.runtimeID {
        case .ollama:
            if path.hasPrefix("logs/") || components.first == "logs" { return .logs }
            if path.contains("models/manifests/") || components.first == "manifests" { return .manifests }
            if path.contains("models/blobs/") || components.first == "blobs" { return .weights }
            return .applicationState
        case .lmStudio:
            if components.first == "models" || descriptor.modelRoot.map({ AIModelsDiscovery.contains($0, item.url) }) == true {
                if ["gguf", "safetensors", "bin"].contains(ext) { return .weights }
                return .manifests
            }
            if path.hasPrefix("extensions/backends/") || path.hasPrefix("extensions/frameworks/")
                || components.first == "bin" { return .runtimes }
            if components.first == "server-logs" || path.contains("crashpad/") { return .logs }
            if components.first == "conversations" || path.contains("local storage/")
                || path.contains("indexeddb/") { return .chats }
            if components.first == "config-presets" || path.hasPrefix("hub/presets/") { return .manifests }
            return .applicationState
        case .huggingFace:
            if path.contains("/blobs/") { return .weights }
            if path.contains("/refs/") || path.contains("/snapshots/") { return .manifests }
            return .applicationState
        case .llamaCpp:
            return .runtimes
        case .standalone:
            return .weights
        default:
            return .other
        }
    }

    private func relativeComponents(from root: URL, to child: URL) -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count >= rootComponents.count else { return [] }
        return Array(childComponents.dropFirst(rootComponents.count))
    }
}

private struct AIModelsObservationSnapshot: Sendable {
    let categoryMetrics: [AIModelRuntimeID: [AIModelStorageCategory: AIModelsMutableMetrics]]
    let candidates: [String: [ScannedFileItem]]
    let huggingFaceRepos: [String: AIModelsHubRepoObservation]
}

private struct AIModelsHubRepoObservation: Sendable {
    var metrics = AIModelsMutableMetrics()
    var extensions: Set<String> = []
    var quantizations: Set<String> = []
    var largeDigests: Set<String> = []
}

private struct AIModelsMutableMetrics: Equatable, Sendable {
    var size: Int64 = 0
    var itemCount = 0
    var latestModificationDate: Date?

    mutating func record(_ item: ScannedFileItem) {
        size = safeMetricAdd(size, item.size)
        itemCount = safeMetricAdd(itemCount, 1)
        if let date = item.modificationDate,
           latestModificationDate == nil || date > latestModificationDate! {
            latestModificationDate = date
        }
    }
}

private func safeMetricAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int64.max : result.partialValue
}

private func safeMetricAdd(_ left: Int, _ right: Int) -> Int {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int.max : result.partialValue
}
