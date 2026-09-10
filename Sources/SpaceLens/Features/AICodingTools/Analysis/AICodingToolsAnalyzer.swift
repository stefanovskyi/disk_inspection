import Darwin
import Foundation

struct AICodingToolsRequest: Sendable {
    let homeDirectory: URL
    let applicationSupportDirectory: URL
    let environment: [String: String]
    let projectRoots: [URL]
    let applicationDirectories: [URL]
    let homebrewPrefixes: [URL]

    init(
        homeDirectory: URL,
        applicationSupportDirectory: URL,
        environment: [String: String],
        projectRoots: [URL],
        applicationDirectories: [URL] = [],
        homebrewPrefixes: [URL] = []
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.applicationSupportDirectory = applicationSupportDirectory.standardizedFileURL
        self.environment = environment
        self.projectRoots = projectRoots.map(\.standardizedFileURL)
        self.applicationDirectories = applicationDirectories.map(\.standardizedFileURL)
        self.homebrewPrefixes = homebrewPrefixes.map(\.standardizedFileURL)
    }

    static func currentUser(projectRoots: [URL] = []) -> Self {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? homeDirectory.appendingPathComponent("Library/Application Support")
        return Self(
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportDirectory.standardizedFileURL,
            environment: ProcessInfo.processInfo.environment,
            projectRoots: projectRoots.map(\.standardizedFileURL),
            applicationDirectories: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeDirectory.appendingPathComponent("Applications", isDirectory: true)
            ],
            homebrewPrefixes: [
                URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
                URL(fileURLWithPath: "/usr/local", isDirectory: true)
            ]
        )
    }
}

protocol AICodingToolsAnalyzing: Sendable {
    func analyze(
        request: AICodingToolsRequest,
        onProgress: @escaping @Sendable (AICodingToolsProgress) -> Void
    ) async throws -> AICodingToolsReport
}

struct AICodingToolsAnalyzer: AICodingToolsAnalyzing, @unchecked Sendable {
    typealias ProgressHandler = @Sendable (AICodingToolsProgress) -> Void

    private let scanner: DiskScanner
    private let installationsDetector: any AICodingInstallationsDetecting
    private let fixedRootDescriptors: [AICodingRootDescriptor]?

    init(
        scanner: DiskScanner = DiskScanner(),
        installationsDetector: any AICodingInstallationsDetecting = AICodingInstallationsDetector(),
        rootDescriptors: [AICodingRootDescriptor]? = nil
    ) {
        self.scanner = scanner
        self.installationsDetector = installationsDetector
        fixedRootDescriptors = rootDescriptors
    }

    func analyze(
        request: AICodingToolsRequest,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> AICodingToolsReport {
        let startedAt = Date()
        async let detectedInstallations = installationsDetector.detect(request: request)
        let catalogDescriptors = Self.normalizedDescriptors(
            fixedRootDescriptors ?? AICodingToolsCatalog.rootDescriptors(for: request)
        )
        var statuses: [String: AICodingLocationStatus] = [:]

        for descriptor in catalogDescriptors {
            try Task.checkCancellation()
            statuses[descriptor.id] = Self.preflightStatus(for: descriptor)
        }

        let descriptors = Self.collapsedDescriptors(
            catalogDescriptors,
            statuses: statuses
        )
        let existingDescriptors = descriptors.filter { statuses[$0.id] == .measured }
        let accumulator = AICodingObservationAccumulator(descriptors: existingDescriptors)
        let scanRoots = Self.nonOverlappingScanRoots(from: existingDescriptors)
        var scans: [String: AICodingPhysicalScan] = [:]
        var completedLocations = 0

        for scanRoot in scanRoots {
            try Task.checkCancellation()
            let completedBeforeScan = completedLocations
            let containedDescriptors = existingDescriptors.filter {
                Self.contains(scanRoot.url, $0.url)
            }
            let progressToolID = Self.mostSpecificDescriptor(
                for: scanRoot.url,
                in: containedDescriptors
            )?.toolID ?? scanRoot.toolID
            let progressTool = AICodingToolsCatalog.metadata(for: progressToolID)
            let baseProgress = AICodingToolsProgress(
                currentTool: progressTool,
                currentLocationName: scanRoot.name,
                currentPath: scanRoot.url.path,
                completedLocations: completedBeforeScan,
                totalLocations: scanRoots.count,
                itemsScanned: accumulator.snapshot().itemCount,
                mappedBytes: accumulator.snapshot().size
            )
            onProgress(baseProgress)

            do {
                let result = try await scanner.scan(
                    url: scanRoot.url,
                    retaining: containedDescriptors.map(\.url),
                    onItem: { item in accumulator.record(item) },
                    onProgress: { scanProgress in
                        let totals = accumulator.snapshot()
                        onProgress(
                            AICodingToolsProgress(
                                currentTool: progressTool,
                                currentLocationName: scanRoot.name,
                                currentPath: scanProgress.currentPath,
                                completedLocations: completedBeforeScan,
                                totalLocations: scanRoots.count,
                                itemsScanned: totals.itemCount,
                                mappedBytes: totals.size
                            )
                        )
                    }
                )
                let status: AICodingLocationStatus
                if result.diagnostics.providerTimeouts > 0 {
                    status = .stalled
                } else if result.unreadableItems > 0 {
                    status = .unreadable
                } else {
                    status = .measured
                }
                scans[scanRoot.url.standardizedFileURL.path] = AICodingPhysicalScan(
                    result: result,
                    status: status
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch ScanFailure.cancelled {
                throw CancellationError()
            } catch {
                scans[scanRoot.url.standardizedFileURL.path] = AICodingPhysicalScan(
                    result: nil,
                    status: .unreadable
                )
            }

            completedLocations += 1
            let totals = accumulator.snapshot()
            onProgress(
                AICodingToolsProgress(
                    currentTool: progressTool,
                    currentLocationName: scanRoot.name,
                    currentPath: scanRoot.url.path,
                    completedLocations: completedLocations,
                    totalLocations: scanRoots.count,
                    itemsScanned: totals.itemCount,
                    mappedBytes: totals.size
                )
            )
        }

        try Task.checkCancellation()
        let installationsByTool = try await detectedInstallations
        let tools = Self.reportTools(
            descriptors: descriptors,
            statuses: statuses,
            aggregates: accumulator.locationSnapshots(),
            scans: scans,
            installationsByTool: installationsByTool
        )
        return AICodingToolsReport(
            tools: tools,
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private static func reportTools(
        descriptors: [AICodingRootDescriptor],
        statuses: [String: AICodingLocationStatus],
        aggregates: [String: [AICodingStorageCategory: AICodingMutableMetrics]],
        scans: [String: AICodingPhysicalScan],
        installationsByTool: [AICodingToolID: [AICodingToolInstallation]]
    ) -> [AICodingToolReport] {
        var toolOrder = AICodingToolsCatalog.supportedTools.map(\.id)
        for descriptor in descriptors where !toolOrder.contains(descriptor.toolID) {
            toolOrder.append(descriptor.toolID)
        }

        return toolOrder.map { toolID in
            let locations = descriptors.filter { $0.toolID == toolID }.map { descriptor in
                let categories = (aggregates[descriptor.id] ?? [:]).map { category, metrics in
                    AICodingCategoryBreakdown(
                        category: category,
                        size: metrics.size,
                        itemCount: metrics.itemCount,
                        latestModificationDate: metrics.latestModificationDate
                    )
                }
                .sorted {
                    if $0.size == $1.size {
                        return $0.category.displayName < $1.category.displayName
                    }
                    return $0.size > $1.size
                }
                let physicalScan = scans.first { path, _ in
                    contains(URL(fileURLWithPath: path, isDirectory: true), descriptor.url)
                }?.value
                let scanRoot = physicalScan?.result?.root.node(at: descriptor.url)
                let preflightStatus = statuses[descriptor.id] ?? .missing
                return AICodingStorageLocation(
                    toolID: descriptor.toolID,
                    name: descriptor.name,
                    url: descriptor.url,
                    explanation: descriptor.explanation,
                    status: preflightStatus == .measured
                        ? physicalScan?.status ?? .unreadable
                        : preflightStatus,
                    root: scanRoot,
                    categories: categories,
                    defaultCategory: descriptor.defaultCategory,
                    rules: descriptor.rules
                )
            }
            .sorted {
                if $0.size == $1.size { return $0.name < $1.name }
                return $0.size > $1.size
            }
            return AICodingToolReport(
                tool: AICodingToolsCatalog.metadata(for: toolID),
                locations: locations,
                installations: installationsByTool[toolID] ?? []
            )
        }
    }

    private static func preflightStatus(
        for descriptor: AICodingRootDescriptor
    ) -> AICodingLocationStatus {
        let url = descriptor.url
        if hasSymbolicLinkComponent(
            url,
            below: descriptor.symlinkBoundaryURL ?? url.deletingLastPathComponent()
        ) {
            return .linked
        }
        do {
            let metadata = try LowLevelMetadataReader.metadata(at: url)
            return metadata.kind == .directory ? .measured : .unreadable
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain,
               error.code == Int(ENOENT) || error.code == Int(ENOTDIR) {
                return .missing
            }
            return .unreadable
        }
    }

    private static func hasSymbolicLinkComponent(_ url: URL, below boundary: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let standardizedBoundary = boundary.standardizedFileURL
        guard contains(standardizedBoundary, standardizedURL) else { return true }
        let components = standardizedURL.pathComponents.dropFirst(
            standardizedBoundary.pathComponents.count
        )
        var candidate = standardizedBoundary
        for component in components {
            candidate.appendPathComponent(component)
            do {
                if try LowLevelMetadataReader.metadata(at: candidate).kind == .symbolicLink {
                    return true
                }
            } catch let error as NSError {
                if error.domain == NSPOSIXErrorDomain,
                   error.code == Int(ENOENT) || error.code == Int(ENOTDIR) {
                    return false
                }
            }
        }
        return false
    }

    private static func normalizedDescriptors(
        _ descriptors: [AICodingRootDescriptor]
    ) -> [AICodingRootDescriptor] {
        var result: [AICodingRootDescriptor] = []
        var indicesByID: [String: Int] = [:]

        for source in descriptors {
            let descriptor = source.standardized()
            if let index = indicesByID[descriptor.id] {
                let existing = result[index]
                let rules = existing.rules + descriptor.rules.filter { !existing.rules.contains($0) }
                result[index] = AICodingRootDescriptor(
                    toolID: existing.toolID,
                    name: existing.name,
                    url: existing.url,
                    explanation: existing.explanation,
                    defaultCategory: existing.defaultCategory,
                    rules: rules,
                    symlinkBoundaryURL: existing.symlinkBoundaryURL
                )
            } else {
                indicesByID[descriptor.id] = result.count
                result.append(descriptor)
            }
        }
        return result
    }

    private static func collapsedDescriptors(
        _ descriptors: [AICodingRootDescriptor],
        statuses: [String: AICodingLocationStatus]
    ) -> [AICodingRootDescriptor] {
        var toolOrder = AICodingToolsCatalog.supportedTools.map(\.id)
        for descriptor in descriptors where !toolOrder.contains(descriptor.toolID) {
            toolOrder.append(descriptor.toolID)
        }

        return toolOrder.flatMap { toolID in
            let toolDescriptors = descriptors.filter { $0.toolID == toolID }
            let measured = toolDescriptors
                .filter { statuses[$0.id] == .measured }
                .sorted(by: descriptorDepthOrder)
            let unavailable = toolDescriptors
                .filter { statuses[$0.id] != .measured }
                .sorted(by: descriptorDepthOrder)
            var result: [AICodingRootDescriptor] = []

            for descriptor in measured + unavailable {
                if let index = result.firstIndex(where: {
                    contains($0.url, descriptor.url)
                        && statuses[$0.id] == .measured
                }) {
                    result[index] = result[index].absorbing(descriptor)
                } else {
                    result.append(descriptor)
                }
            }
            return result
        }
    }

    private static func descriptorDepthOrder(
        _ left: AICodingRootDescriptor,
        _ right: AICodingRootDescriptor
    ) -> Bool {
        let leftDepth = left.url.pathComponents.count
        let rightDepth = right.url.pathComponents.count
        if leftDepth == rightDepth { return left.url.path < right.url.path }
        return leftDepth < rightDepth
    }

    private static func nonOverlappingScanRoots(
        from descriptors: [AICodingRootDescriptor]
    ) -> [AICodingRootDescriptor] {
        let ordered = descriptors.enumerated().sorted { left, right in
            let leftDepth = left.element.url.pathComponents.count
            let rightDepth = right.element.url.pathComponents.count
            if leftDepth == rightDepth { return left.offset < right.offset }
            return leftDepth < rightDepth
        }
        var roots: [AICodingRootDescriptor] = []
        for candidate in ordered.map(\.element) {
            if roots.contains(where: { contains($0.url, candidate.url) }) { continue }
            roots.append(candidate)
        }
        return roots.sorted { $0.url.path < $1.url.path }
    }

    static func mostSpecificDescriptor(
        for url: URL,
        in descriptors: [AICodingRootDescriptor]
    ) -> AICodingRootDescriptor? {
        descriptors.enumerated()
            .filter { contains($0.element.url, url) }
            .sorted { left, right in
                let leftDepth = left.element.url.pathComponents.count
                let rightDepth = right.element.url.pathComponents.count
                if leftDepth == rightDepth { return left.offset < right.offset }
                return leftDepth > rightDepth
            }
            .first?
            .element
    }

    static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        if parentPath == childPath { return true }
        if parentPath == "/" { return childPath.hasPrefix("/") }
        return childPath.hasPrefix(parentPath + "/")
    }
}


private final class AICodingObservationAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let descriptors: [AICodingRootDescriptor]
    private var values: [String: [AICodingStorageCategory: AICodingMutableMetrics]] = [:]
    private var overall = AICodingMutableMetrics()

    init(descriptors: [AICodingRootDescriptor]) {
        self.descriptors = descriptors
    }

    func record(_ item: ScannedFileItem) {
        lock.lock()
        overall.record(item)
        for descriptor in descriptors where AICodingToolsAnalyzer.contains(descriptor.url, item.url) {
            let category = descriptor.category(for: item.url)
            var categoryValues = values[descriptor.id] ?? [:]
            var metrics = categoryValues[category] ?? AICodingMutableMetrics()
            metrics.record(item)
            categoryValues[category] = metrics
            values[descriptor.id] = categoryValues
        }
        lock.unlock()
    }

    func snapshot() -> AICodingMutableMetrics {
        lock.lock()
        defer { lock.unlock() }
        return overall
    }

    func locationSnapshots() -> [String: [AICodingStorageCategory: AICodingMutableMetrics]] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private struct AICodingPhysicalScan: Sendable {
    let result: ScanResult?
    let status: AICodingLocationStatus
}

struct AICodingMutableMetrics: Equatable, Sendable {
    var size: Int64 = 0
    var itemCount = 0
    var latestModificationDate: Date?

    mutating func record(_ item: ScannedFileItem) {
        let sizeResult = size.addingReportingOverflow(item.size)
        size = sizeResult.overflow ? Int64.max : sizeResult.partialValue
        let itemResult = itemCount.addingReportingOverflow(1)
        itemCount = itemResult.overflow ? Int.max : itemResult.partialValue
        if let date = item.modificationDate,
           latestModificationDate == nil || date > latestModificationDate! {
            latestModificationDate = date
        }
    }

    mutating func merge(_ other: Self) {
        let sizeResult = size.addingReportingOverflow(other.size)
        size = sizeResult.overflow ? Int64.max : sizeResult.partialValue
        let itemResult = itemCount.addingReportingOverflow(other.itemCount)
        itemCount = itemResult.overflow ? Int.max : itemResult.partialValue
        if let date = other.latestModificationDate,
           latestModificationDate == nil || date > latestModificationDate! {
            latestModificationDate = date
        }
    }
}
