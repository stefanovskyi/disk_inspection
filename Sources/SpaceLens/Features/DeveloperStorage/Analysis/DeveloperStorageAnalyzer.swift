import Darwin
import Foundation

struct DeveloperStorageAnalyzer: DeveloperStorageAnalyzing, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (DeveloperStorageProgress) -> Void

    private let scanner: DiskScanner
    private let fixedDescriptors: [DeveloperArtifactDescriptor]?

    init(
        scanner: DiskScanner = DiskScanner(),
        descriptors: [DeveloperArtifactDescriptor]? = nil
    ) {
        self.scanner = scanner
        fixedDescriptors = descriptors
    }

    func analyze(
        request: DeveloperStorageRequest,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> DeveloperStorageReport {
        let startedAt = Date()
        var discoveryIssues = 0
        var discoveredDescriptors: [DeveloperArtifactDescriptor] = []
        let sharedDescriptors = fixedDescriptors == nil
            ? DeveloperStorageCatalog.sharedDescriptors(for: request)
            : []
        let knownSharedRoots = sharedDescriptors.map(\.url)

        if fixedDescriptors == nil {
            let containers = request.automaticProjectContainers.map {
                DeveloperDiscoveryContainer(url: $0, isAutomatic: true)
            } + request.projectContainers.map {
                DeveloperDiscoveryContainer(url: $0, isAutomatic: false)
            }
            for discoveryContainer in Self.normalizedContainers(containers) {
                try Task.checkCancellation()
                let container = discoveryContainer.url
                let candidates = DeveloperCandidateAccumulator()
                let discoveredBeforeContainer = discoveredDescriptors.count
                onProgress(
                    DeveloperStorageProgress(
                        currentLocationName: "Discovering developer artifacts",
                        currentPath: container.path,
                        discoveredArtifacts: discoveredDescriptors.count
                    )
                )
                do {
                    let result = try await scanner.scanForDirectories(
                        url: container,
                        pruningDirectoryNames: DeveloperStorageCatalog.candidateDirectoryNames.union(
                            discoveryContainer.isAutomatic
                                ? DeveloperStorageCatalog.automaticHomePruningDirectoryNames
                                : []
                        ),
                        onItem: { item in
                            if (item.kind == .directory || item.kind == .symbolicLink),
                               DeveloperStorageCatalog.candidateDirectoryNames.contains(item.url.lastPathComponent) {
                                candidates.record(item.url)
                            }
                        },
                        onProgress: { progress in
                            onProgress(
                                DeveloperStorageProgress(
                                    currentLocationName: "Discovering developer artifacts",
                                    currentPath: progress.currentPath,
                                    discoveredArtifacts: discoveredBeforeContainer + candidates.count,
                                    itemsScanned: progress.itemsScanned
                                )
                            )
                        }
                    )
                    discoveryIssues += result.scan.unreadableItems
                    if result.scan.diagnostics.providerTimeouts > 0 {
                        discoveryIssues += result.scan.diagnostics.providerTimeouts
                    }
                    if result.wasTruncated { discoveryIssues += 1 }
                } catch is CancellationError {
                    throw CancellationError()
                } catch ScanFailure.cancelled {
                    throw CancellationError()
                } catch {
                    discoveryIssues += 1
                }

                discoveredDescriptors.append(contentsOf: candidates.urls.compactMap {
                    DeveloperStorageCatalog.discoveredDescriptor(
                        for: $0,
                        inside: container,
                        request: request,
                        isAutomaticContainer: discoveryContainer.isAutomatic,
                        knownSharedRoots: knownSharedRoots
                    )
                })
            }
        }

        let catalogDescriptors = fixedDescriptors
            ?? sharedDescriptors + discoveredDescriptors
        let descriptors = Self.normalizedDescriptors(catalogDescriptors)
            .filter { Self.preflightStatus(for: $0) != nil }
            .sorted(by: Self.scanOrder)
        let discoveredArtifactCount = discoveredDescriptors.count
        let accumulator = DeveloperStorageObservationAccumulator()
        var locations: [DeveloperStorageLocation] = []

        for (index, descriptor) in descriptors.enumerated() {
            try Task.checkCancellation()
            let preflight = Self.preflightStatus(for: descriptor) ?? .unreadable
            let baseProgress = DeveloperStorageProgress(
                currentEcosystem: descriptor.ecosystemID,
                currentLocationName: descriptor.name,
                currentPath: descriptor.url.path,
                discoveredArtifacts: discoveredArtifactCount,
                completedLocations: index,
                totalLocations: descriptors.count,
                itemsScanned: accumulator.snapshot.items,
                mappedBytes: accumulator.snapshot.uniqueBytes
            )
            onProgress(baseProgress)

            guard preflight == .measured else {
                locations.append(Self.emptyLocation(descriptor, status: preflight))
                continue
            }

            let locationAccumulator = accumulator.beginLocation(descriptor)
            var result: ScanResult?
            var status: DeveloperStorageLocationStatus = .measured
            do {
                result = try await scanner.scan(
                    url: descriptor.url,
                    onItem: { item in locationAccumulator.record(item) },
                    onProgress: { progress in
                        let totals = accumulator.snapshot
                        onProgress(
                            DeveloperStorageProgress(
                                currentEcosystem: descriptor.ecosystemID,
                                currentLocationName: descriptor.name,
                                currentPath: progress.currentPath,
                                discoveredArtifacts: discoveredArtifactCount,
                                completedLocations: index,
                                totalLocations: descriptors.count,
                                itemsScanned: totals.items,
                                mappedBytes: totals.uniqueBytes
                            )
                        )
                    }
                )
                if let result, result.diagnostics.providerTimeouts > 0 {
                    status = .stalled
                } else if let result, result.unreadableItems > 0 {
                    status = .unreadable
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch ScanFailure.cancelled {
                throw CancellationError()
            } catch {
                status = .unreadable
            }

            let metrics = locationAccumulator.snapshot
            if status != .measured || metrics.referencedBytes > 0 {
                locations.append(
                    DeveloperStorageLocation(
                        ecosystemID: descriptor.ecosystemID,
                        scope: descriptor.scope,
                        evidence: descriptor.evidence,
                        kind: descriptor.kind,
                        name: descriptor.name,
                        url: descriptor.url,
                        projectURL: descriptor.projectURL,
                        uniqueSize: metrics.uniqueBytes,
                        referencedSize: metrics.referencedBytes,
                        itemCount: metrics.items,
                        latestModificationDate: metrics.latestModificationDate,
                        status: status,
                        root: result?.root,
                        breakdowns: metrics.breakdowns
                    )
                )
            }
            let totals = accumulator.snapshot
            onProgress(
                DeveloperStorageProgress(
                    currentEcosystem: descriptor.ecosystemID,
                    currentLocationName: descriptor.name,
                    currentPath: descriptor.url.path,
                    discoveredArtifacts: discoveredArtifactCount,
                    completedLocations: index + 1,
                    totalLocations: descriptors.count,
                    itemsScanned: totals.items,
                    mappedBytes: totals.uniqueBytes
                )
            )
        }

        let reports = DeveloperEcosystemID.allCases.map { ecosystem in
            DeveloperEcosystemReport(
                ecosystemID: ecosystem,
                locations: locations.filter { $0.ecosystemID == ecosystem }
            )
        }
        return DeveloperStorageReport(
            ecosystems: reports,
            startedAt: startedAt,
            discoveryIssueCount: discoveryIssues
        )
    }

    private static func normalizedContainers(
        _ containers: [DeveloperDiscoveryContainer]
    ) -> [DeveloperDiscoveryContainer] {
        var values: [String: DeveloperDiscoveryContainer] = [:]
        for container in containers {
            let standardized = container.url.standardizedFileURL
            let value = DeveloperDiscoveryContainer(
                url: standardized,
                isAutomatic: container.isAutomatic
            )
            if values[standardized.path]?.isAutomatic == true && !container.isAutomatic {
                values[standardized.path] = value
            } else if values[standardized.path] == nil {
                values[standardized.path] = value
            }
        }
        return values.values.sorted { $0.url.path < $1.url.path }
    }

    private static func normalizedDescriptors(
        _ descriptors: [DeveloperArtifactDescriptor]
    ) -> [DeveloperArtifactDescriptor] {
        var seen: Set<String> = []
        return descriptors.filter { seen.insert($0.id).inserted }
    }

    private static func scanOrder(
        _ left: DeveloperArtifactDescriptor,
        _ right: DeveloperArtifactDescriptor
    ) -> Bool {
        if left.scope != right.scope { return left.scope.scanPriority < right.scope.scanPriority }
        if left.ecosystemID != right.ecosystemID {
            return left.ecosystemID.rawValue < right.ecosystemID.rawValue
        }
        return left.url.path < right.url.path
    }

    private static func preflightStatus(
        for descriptor: DeveloperArtifactDescriptor
    ) -> DeveloperStorageLocationStatus? {
        let boundary = descriptor.symlinkBoundaryURL ?? descriptor.url.deletingLastPathComponent()
        if hasSymbolicLinkComponent(descriptor.url, below: boundary) { return .linked }
        do {
            let metadata = try LowLevelMetadataReader.metadata(at: descriptor.url)
            return metadata.kind == .directory ? .measured : .unreadable
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain,
               error.code == Int(ENOENT) || error.code == Int(ENOTDIR) {
                return nil
            }
            return .unreadable
        }
    }

    private static func hasSymbolicLinkComponent(_ url: URL, below boundary: URL) -> Bool {
        let target = url.standardizedFileURL
        let root = boundary.standardizedFileURL
        guard DeveloperStorageCatalog.contains(root, target) else { return true }
        let components = target.pathComponents.dropFirst(root.pathComponents.count)
        var candidate = root
        for component in components {
            candidate.appendPathComponent(component)
            do {
                if try LowLevelMetadataReader.metadata(at: candidate).kind == .symbolicLink { return true }
            } catch let error as NSError {
                if error.domain == NSPOSIXErrorDomain,
                   error.code == Int(ENOENT) || error.code == Int(ENOTDIR) { return false }
            }
        }
        return false
    }

    private static func emptyLocation(
        _ descriptor: DeveloperArtifactDescriptor,
        status: DeveloperStorageLocationStatus
    ) -> DeveloperStorageLocation {
        DeveloperStorageLocation(
            ecosystemID: descriptor.ecosystemID,
            scope: descriptor.scope,
            evidence: descriptor.evidence,
            kind: descriptor.kind,
            name: descriptor.name,
            url: descriptor.url,
            projectURL: descriptor.projectURL,
            uniqueSize: 0,
            referencedSize: 0,
            itemCount: 0,
            latestModificationDate: nil,
            status: status,
            root: nil,
            breakdowns: []
        )
    }
}

private struct DeveloperDiscoveryContainer: Sendable {
    let url: URL
    let isAutomatic: Bool
}

private final class DeveloperCandidateAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String: URL] = [:]

    func record(_ url: URL) {
        lock.lock()
        paths[url.standardizedFileURL.path] = url.standardizedFileURL
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return paths.count
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return paths.values.sorted { $0.path < $1.path }
    }
}

private final class DeveloperStorageObservationAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var identities: Set<FileIdentity> = []
    private var pathsWithoutIdentity: Set<String> = []
    private var uniqueBytes: Int64 = 0
    private var items = 0

    var snapshot: (uniqueBytes: Int64, items: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (uniqueBytes, items)
    }

    func beginLocation(_ descriptor: DeveloperArtifactDescriptor) -> DeveloperLocationAccumulator {
        DeveloperLocationAccumulator(owner: self, descriptor: descriptor)
    }

    fileprivate func classify(_ item: ScannedFileItem) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        items = developerAdd(items, 1)
        let isUnique: Bool
        if let identity = item.identity {
            isUnique = identities.insert(identity).inserted
        } else {
            isUnique = pathsWithoutIdentity.insert(item.url.standardizedFileURL.path).inserted
        }
        if isUnique { uniqueBytes = developerAdd(uniqueBytes, item.size) }
        return isUnique
    }
}

private final class DeveloperLocationAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let owner: DeveloperStorageObservationAccumulator
    private let descriptor: DeveloperArtifactDescriptor
    private var metrics = DeveloperLocationMetrics()

    init(owner: DeveloperStorageObservationAccumulator, descriptor: DeveloperArtifactDescriptor) {
        self.owner = owner
        self.descriptor = descriptor
    }

    func record(_ item: ScannedFileItem) {
        let isUnique = owner.classify(item)
        let kind = descriptor.category(for: item.url)
        lock.lock()
        metrics.record(item, kind: kind, isUnique: isUnique)
        lock.unlock()
    }

    var snapshot: DeveloperLocationMetrics {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }
}

private struct DeveloperLocationMetrics: Sendable {
    var uniqueBytes: Int64 = 0
    var referencedBytes: Int64 = 0
    var items = 0
    var latestModificationDate: Date?
    private var byKind: [DeveloperArtifactKind: DeveloperKindMetrics] = [:]

    mutating func record(_ item: ScannedFileItem, kind: DeveloperArtifactKind, isUnique: Bool) {
        referencedBytes = developerAdd(referencedBytes, item.size)
        if isUnique { uniqueBytes = developerAdd(uniqueBytes, item.size) }
        items = developerAdd(items, 1)
        if let date = item.modificationDate,
           latestModificationDate == nil || date > latestModificationDate! {
            latestModificationDate = date
        }
        var category = byKind[kind] ?? DeveloperKindMetrics()
        category.referencedBytes = developerAdd(category.referencedBytes, item.size)
        if isUnique { category.uniqueBytes = developerAdd(category.uniqueBytes, item.size) }
        category.items = developerAdd(category.items, 1)
        byKind[kind] = category
    }

    var breakdowns: [DeveloperStorageBreakdown] {
        byKind.map { kind, value in
            DeveloperStorageBreakdown(
                kind: kind,
                uniqueSize: value.uniqueBytes,
                referencedSize: value.referencedBytes,
                itemCount: value.items
            )
        }
        .sorted { $0.uniqueSize == $1.uniqueSize ? $0.kind.rawValue < $1.kind.rawValue : $0.uniqueSize > $1.uniqueSize }
    }
}

private struct DeveloperKindMetrics: Sendable {
    var uniqueBytes: Int64 = 0
    var referencedBytes: Int64 = 0
    var items = 0
}

private func developerAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int64.max : result.partialValue
}

private func developerAdd(_ left: Int, _ right: Int) -> Int {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int.max : result.partialValue
}
