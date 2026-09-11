import Darwin
import Foundation

struct FileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct ScanScope: Sendable {
    let rootPath: String
    let rootDevice: UInt64?
    let excludedPaths: Set<String>

    private static let logicalRootExclusions = [
        "/.vol",
        "/dev",
        "/home",
        "/net",
        "/Network",
        "/System/Volumes",
        "/Volumes"
    ]

    func allows(path: String, identity: FileIdentity?) -> Bool {
        if path == rootPath { return true }

        if excludedPaths.contains(where: {
            path == $0 || path.hasPrefix("\($0)/")
        }) {
            return false
        }

        if rootPath == "/", Self.logicalRootExclusions.contains(where: {
            path == $0 || path.hasPrefix("\($0)/")
        }) {
            return false
        }

        if let rootDevice, let identity, identity.device != rootDevice {
            return false
        }

        return true
    }
}

struct DirectoryDiscoveryBudget: Equatable, Sendable {
    let maximumDepth: Int
    let maximumDirectories: Int
    let maximumDuration: TimeInterval

    init(
        maximumDepth: Int = 18,
        maximumDirectories: Int = 100_000,
        maximumDuration: TimeInterval = 60
    ) {
        precondition(maximumDepth >= 0)
        precondition(maximumDirectories > 0)
        precondition(maximumDuration > 0)
        self.maximumDepth = maximumDepth
        self.maximumDirectories = maximumDirectories
        self.maximumDuration = maximumDuration
    }
}

struct DirectoryDiscoveryScanResult: Sendable {
    let scan: ScanResult
    let wasTruncated: Bool
}

struct DiskScanner {
    typealias ProgressHandler = @Sendable (ScanProgress) -> Void
    typealias ItemHandler = @Sendable (ScannedFileItem) -> Void
    typealias SubtreeIsolationPredicate = @Sendable (URL) -> Bool
    typealias DirectoryReader = @Sendable (URL, [URLResourceKey]) throws -> [URL]
    static let retainedChildLimit = 96

    private let configuration: ScannerConfiguration

    init(
        maximumParallelism: Int? = nil,
        directoryBufferSize: Int = BulkDirectoryReader.defaultBufferSize,
        stalledSubtreeTimeout: TimeInterval = 5,
        shouldIsolateSubtree: SubtreeIsolationPredicate? = nil,
        directoryReader: DirectoryReader? = nil,
        excludedURLs: [URL] = []
    ) {
        let suggestedParallelism = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        precondition(directoryBufferSize >= BulkDirectoryReader.minimumBufferSize)
        configuration = ScannerConfiguration(
            maximumParallelism: max(maximumParallelism ?? suggestedParallelism, 1),
            directoryBufferSize: directoryBufferSize,
            stalledSubtreeTimeout: stalledSubtreeTimeout,
            shouldIsolateSubtree: shouldIsolateSubtree ?? { url in
                Self.shouldIsolateProtectedSubtree(url)
            },
            directoryReader: directoryReader,
            excludedPaths: Set(excludedURLs.map { $0.standardizedFileURL.path })
        )
    }

    func scan(
        url: URL,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> ScanResult {
        try await runScan(url: url, retaining: [], onItem: nil, onProgress: onProgress)
    }

    func scan(
        url: URL,
        onItem: @escaping ItemHandler,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> ScanResult {
        try await runScan(url: url, retaining: [], onItem: onItem, onProgress: onProgress)
    }

    func scan(
        url: URL,
        retaining retainedURLs: [URL],
        onItem: @escaping ItemHandler,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> ScanResult {
        try await runScan(
            url: url,
            retaining: retainedURLs,
            onItem: onItem,
            onProgress: onProgress
        )
    }

    /// Traverses a directory with the normal scanner safety guarantees while
    /// treating matching child directories as opaque discovery candidates.
    /// The candidate directory itself is emitted through `onItem`, but its
    /// descendants are not visited.
    func scanForDirectories(
        url: URL,
        pruningDirectoryNames: Set<String>,
        budget: DirectoryDiscoveryBudget = DirectoryDiscoveryBudget(),
        onItem: @escaping ItemHandler,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> DirectoryDiscoveryScanResult {
        let limiter = DirectoryDiscoveryLimiter(rootURL: url, budget: budget)
        let result = try await runScan(
            url: url,
            retaining: [],
            pruningDirectoryNames: pruningDirectoryNames,
            discoveryLimiter: limiter,
            onItem: onItem,
            onProgress: onProgress
        )
        return DirectoryDiscoveryScanResult(scan: result, wasTruncated: limiter.wasTruncated)
    }

    private func runScan(
        url: URL,
        retaining retainedURLs: [URL],
        pruningDirectoryNames: Set<String> = [],
        discoveryLimiter: DirectoryDiscoveryLimiter? = nil,
        onItem: ItemHandler?,
        onProgress: @escaping ProgressHandler
    ) async throws -> ScanResult {
        let configuration = configuration
        let standardizedURL = url.standardizedFileURL
        let worker = Task.detached(priority: .userInitiated) {
            let signposter = SpaceLensSignposts.scan
            let signpostID = signposter.makeSignpostID()
            let signpostState = signposter.beginInterval(
                "Scan",
                id: signpostID,
                "parallelism=\(configuration.maximumParallelism)"
            )
            var diagnosticSession: ScanSession?
            defer {
                if let diagnostics = diagnosticSession?.diagnosticSnapshot() {
                    signposter.emitEvent(
                        "ScanSyscallCounters",
                        id: signpostID,
                        "batches=\(diagnostics.syscallBatches) fallbackLstat=\(diagnostics.fallbackLstatCalls) bufferAllocations=\(diagnostics.bufferAllocations)"
                    )
                    signposter.emitEvent(
                        "ScanNodeCounters",
                        id: signpostID,
                        "directoryTasks=\(diagnostics.directoryTasks) directories=\(diagnostics.directoryCount) retained=\(diagnostics.retainedNodes) discarded=\(diagnostics.discardedNodes)"
                    )
                    signposter.emitEvent(
                        "ScanProgressCounters",
                        id: signpostID,
                        "merges=\(diagnostics.progressMerges) emissions=\(diagnostics.progressEmissions)"
                    )
                    signposter.emitEvent(
                        "ScanProviderCounters",
                        id: signpostID,
                        "timeouts=\(diagnostics.providerTimeouts) abandonedWorkers=\(diagnostics.abandonedWorkers)"
                    )
                }
                signposter.endInterval("Scan", signpostState)
            }

            let start = Date()
            let rootMetadata = try? LowLevelMetadataReader.metadata(at: standardizedURL)
            let session = ScanSession(
                progress: ScanProgress(currentPath: standardizedURL.path),
                rootURL: standardizedURL,
                rootName: rootMetadata?.name ?? Self.displayName(for: standardizedURL),
                scope: ScanScope(
                    rootPath: standardizedURL.path,
                    rootDevice: rootMetadata?.identity?.device,
                    excludedPaths: configuration.excludedPaths
                ),
                configuration: configuration,
                priorityPaths: Set(retainedURLs.map { $0.standardizedFileURL.path }),
                pruningDirectoryNames: pruningDirectoryNames,
                discoveryLimiter: discoveryLimiter,
                itemHandler: onItem
            )
            diagnosticSession = session

            do {
                guard let root = try await Self.inspect(
                    standardizedURL,
                    knownMetadata: rootMetadata,
                    session: session,
                    activityMonitor: nil,
                    isInsideIsolatedSubtree: false,
                    ownsWorkerPermit: false,
                    onProgress: onProgress
                ) else {
                    throw ScanFailure.inaccessible(standardizedURL)
                }
                try Task.checkCancellation()
                let progress = session.progressSnapshot(at: standardizedURL)
                session.recordProgressEmission()
                onProgress(progress)
                signposter.emitEvent(
                    "ScanCompleted",
                    id: signpostID,
                    "items=\(progress.itemsScanned) unreadable=\(progress.unreadableItems)"
                )

                let rssBeforeArenaConstruction = Self.currentResidentMemoryBytes()
                let arenaConstructionStart = DispatchTime.now().uptimeNanoseconds
                let retainedRoot = FileNode(rootURL: standardizedURL, snapshot: root)
                let arenaConstructionEnd = DispatchTime.now().uptimeNanoseconds
                let rssAfterArenaConstruction = withExtendedLifetime(root) {
                    Self.currentResidentMemoryBytes()
                }
                var diagnostics = session.diagnosticSnapshot()
                diagnostics.retainedArenaNodeCount = retainedRoot.storageMetrics.nodeCount
                diagnostics.arenaConstructionDurationSeconds = TimeInterval(
                    arenaConstructionEnd &- arenaConstructionStart
                ) / 1_000_000_000
                diagnostics.rssBeforeArenaConstructionBytes = rssBeforeArenaConstruction
                diagnostics.rssAfterArenaConstructionBytes = rssAfterArenaConstruction
                signposter.emitEvent(
                    "ScanArenaConstruction",
                    id: signpostID,
                    "nodes=\(diagnostics.retainedArenaNodeCount) durationMilliseconds=\(diagnostics.arenaConstructionDurationSeconds * 1_000) rssBefore=\(rssBeforeArenaConstruction) rssAfter=\(rssAfterArenaConstruction)"
                )
                return ScanResult(
                    root: retainedRoot,
                    duration: Date().timeIntervalSince(start),
                    itemsScanned: progress.itemsScanned,
                    unreadableItems: progress.unreadableItems,
                    diagnostics: diagnostics
                )
            } catch is CancellationError {
                throw ScanFailure.cancelled
            } catch let failure as ScanFailure {
                throw failure
            } catch {
                throw ScanFailure.inaccessible(standardizedURL)
            }
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func inspect(
        _ url: URL,
        knownMetadata: LowLevelFileMetadata?,
        session: ScanSession,
        activityMonitor: ScanActivityMonitor?,
        isInsideIsolatedSubtree: Bool,
        ownsWorkerPermit: Bool,
        onProgress: @escaping ProgressHandler
    ) async throws -> FileNodeSnapshot? {
        try Task.checkCancellation()
        guard activityMonitor?.isActive != false else { throw CancellationError() }

        let metadata: LowLevelFileMetadata
        do {
            metadata = try knownMetadata ?? LowLevelMetadataReader.metadata(at: url)
            try Task.checkCancellation()
            guard activityMonitor?.isActive != false else { throw CancellationError() }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard session.recordItem(
                at: url,
                activityMonitor: activityMonitor,
                onProgress: onProgress
            ) else { throw CancellationError() }
            guard session.recordObservation(
                ScannedFileItem.unreadable(at: url),
                activityMonitor: activityMonitor
            ) else { throw CancellationError() }
            session.recordUnreadable(at: url, unresponsive: false, onProgress: onProgress)
            return FileNodeSnapshot(
                name: displayName(for: url),
                size: 0,
                isDirectory: false,
                isReadable: false,
                children: []
            )
        }

        let name = metadata.name
        let isDirectory = metadata.kind == .directory

        if !metadata.isReadable {
            guard session.recordItem(
                at: url,
                activityMonitor: activityMonitor,
                onProgress: onProgress
            ) else { throw CancellationError() }
            guard session.recordObservation(
                ScannedFileItem(url: url, metadata: metadata),
                activityMonitor: activityMonitor
            ) else { throw CancellationError() }
            if isDirectory {
                session.diagnostics.recordDirectory()
            }
            session.recordUnreadable(at: url, unresponsive: false, onProgress: onProgress)
            return FileNodeSnapshot(
                name: name,
                size: 0,
                isDirectory: isDirectory,
                isReadable: false,
                children: []
            )
        }

        guard isDirectory else {
            guard session.recordItem(
                at: url,
                activityMonitor: activityMonitor,
                onProgress: onProgress
            ) else { throw CancellationError() }
            guard session.recordObservation(
                ScannedFileItem(url: url, metadata: metadata),
                activityMonitor: activityMonitor
            ) else { throw CancellationError() }
            if activityMonitor == nil {
                session.mergeMappedBytes(
                    metadata.size,
                    itemCount: 1,
                    within: url.deletingLastPathComponent()
                )
            }
            return FileNodeSnapshot(
                name: name,
                size: metadata.size,
                isDirectory: false,
                isReadable: true,
                children: []
            )
        }

        let identity = metadata.identity
        try Task.checkCancellation()
        guard activityMonitor?.isActive != false else { throw CancellationError() }
        guard session.scope.allows(path: url.path, identity: identity) else { return nil }

        if !isInsideIsolatedSubtree,
           session.configuration.shouldIsolateSubtree(url) {
            return try await inspectIsolatedSubtree(
                url,
                session: session,
                ownsWorkerPermit: ownsWorkerPermit,
                onProgress: onProgress
            )
        }

        if let identity {
            guard session.visitedDirectories.insertIfNew(identity) else { return nil }
        }

        guard session.recordItem(
            at: url,
            activityMonitor: activityMonitor,
            onProgress: onProgress
        ) else { throw CancellationError() }
        guard session.recordObservation(
            ScannedFileItem(url: url, metadata: metadata),
            activityMonitor: activityMonitor
        ) else { throw CancellationError() }
        session.diagnostics.recordDirectory()

        if session.shouldPruneDirectory(at: url) {
            return FileNodeSnapshot(
                name: name,
                size: 0,
                isDirectory: true,
                isReadable: true,
                children: []
            )
        }

        var retainedChildren = BoundedNodeAccumulator(capacity: retainedChildLimit)
        var total: Int64 = 0
        var totalItems = 1
        var measuredDirectItems = 0
        var pendingDirectories: [(entry: LowLevelDirectoryEntry, metadata: LowLevelFileMetadata)] = []
        var progressBatch = ScanProgressBatch(
            session: session,
            activityMonitor: activityMonitor,
            previewURL: url,
            onProgress: onProgress
        )

        let consumeEntry: (LowLevelDirectoryEntry) throws -> Void = { entry in
            try Task.checkCancellation()
            guard activityMonitor?.isActive != false else { throw CancellationError() }

            let entryMetadata: LowLevelFileMetadata
            if let metadata = entry.metadata {
                entryMetadata = metadata
            } else {
                let entryURL = entry.url(relativeTo: url)
                do {
                    session.diagnostics.recordFallbackLstat()
                    entryMetadata = try LowLevelMetadataReader.metadata(at: entryURL)
                } catch {
                    guard progressBatch.recordItem(size: 0, path: { entryURL.path }) else {
                        throw CancellationError()
                    }
                    guard session.recordObservation(
                        ScannedFileItem.unreadable(at: entryURL),
                        activityMonitor: activityMonitor
                    ) else { throw CancellationError() }
                    progressBatch.flush(path: { entryURL.path })
                    session.recordUnreadable(
                        at: entryURL,
                        unresponsive: false,
                        onProgress: onProgress
                    )
                    measuredDirectItems += 1
                    totalItems = addingWithoutOverflow(totalItems, 1)
                    retainedChildren.insert(
                        RetainedNodeCandidate(
                            name: entry.name,
                            size: 0,
                            isDirectory: false,
                            isReadable: false,
                            isPriority: session.shouldPrioritize(entryURL)
                        )
                    )
                    return
                }
            }

            if entryMetadata.kind == .directory, entryMetadata.isReadable {
                pendingDirectories.append((entry, entryMetadata))
                return
            }

            guard progressBatch.recordItem(
                size: entryMetadata.isReadable ? entryMetadata.size : 0,
                path: { entry.url(relativeTo: url).path }
            ) else { throw CancellationError() }
            let entryURL = entry.url(relativeTo: url)
            guard session.recordObservation(
                ScannedFileItem(url: entryURL, metadata: entryMetadata),
                activityMonitor: activityMonitor
            ) else { throw CancellationError() }
            if !entryMetadata.isReadable {
                progressBatch.flush(path: { entryURL.path })
                session.recordUnreadable(
                    path: { entryURL.path },
                    unresponsive: false,
                    onProgress: onProgress
                )
            }
            let size = entryMetadata.isReadable ? entryMetadata.size : 0
            measuredDirectItems += 1
            total = addingWithoutOverflow(total, size)
            totalItems = addingWithoutOverflow(totalItems, 1)
            retainedChildren.insert(
                RetainedNodeCandidate(
                    name: entryMetadata.name,
                    size: size,
                    isDirectory: entryMetadata.kind == .directory,
                    isReadable: entryMetadata.isReadable,
                    isPriority: session.shouldPrioritize(entryURL)
                )
            )
        }

        do {
            if let directoryReader = session.configuration.directoryReader {
                let urls = try directoryReader(url, [])
                for entryURL in urls {
                    session.diagnostics.recordFallbackLstat()
                    try consumeEntry(
                        LowLevelDirectoryEntry(
                            url: entryURL,
                            metadata: try? LowLevelMetadataReader.metadata(at: entryURL)
                        )
                    )
                }
            } else {
                try BulkDirectoryReader.forEachEntry(
                    of: url,
                    using: session.directoryBuffers,
                    diagnostics: session.diagnostics
                ) { entry in
                    try consumeEntry(entry)
                }
            }
            try Task.checkCancellation()
            guard activityMonitor?.isActive != false else { throw CancellationError() }
            progressBatch.flush(path: { url.path })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            progressBatch.flush(path: { url.path })
            session.recordUnreadable(at: url, unresponsive: false, onProgress: onProgress)
            return FileNodeSnapshot(
                name: name,
                size: 0,
                isDirectory: true,
                isReadable: false,
                children: []
            )
        }

        try await withThrowingTaskGroup(of: FileNodeSnapshot?.self) { group in
            var pendingTaskCount = 0

            for pendingDirectory in pendingDirectories {
                try Task.checkCancellation()
                guard activityMonitor?.isActive != false else { throw CancellationError() }
                let entry = pendingDirectory.entry
                let entryMetadata = pendingDirectory.metadata
                let entryURL = entry.url(relativeTo: url)

                var acquiredPermit = session.parallelism.tryAcquire()
                while !acquiredPermit, !ownsWorkerPermit, pendingTaskCount > 0 {
                    if let completedChild = try await group.next() {
                        pendingTaskCount -= 1
                        if let completedChild {
                            session.recordCompletedPreview(completedChild, parentURL: url)
                            measuredDirectItems += 1
                            total = addingWithoutOverflow(total, completedChild.size)
                            totalItems = addingWithoutOverflow(totalItems, completedChild.itemCount)
                            let childURL = url.appendingPathComponent(completedChild.name)
                            retainedChildren.insert(
                                RetainedNodeCandidate(
                                    node: completedChild,
                                    isPriority: session.shouldPrioritize(childURL)
                                )
                            )
                        }
                    }
                    acquiredPermit = session.parallelism.tryAcquire()
                }

                if acquiredPermit {
                    pendingTaskCount += 1
                    session.diagnostics.recordDirectoryTask()
                    group.addTask {
                        defer { session.parallelism.release() }
                        return try await inspect(
                            entryURL,
                            knownMetadata: entryMetadata,
                            session: session,
                            activityMonitor: activityMonitor,
                            isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                            ownsWorkerPermit: true,
                            onProgress: onProgress
                        )
                    }
                } else if let child = try await inspect(
                    entryURL,
                    knownMetadata: entryMetadata,
                    session: session,
                    activityMonitor: activityMonitor,
                    isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                    ownsWorkerPermit: ownsWorkerPermit,
                    onProgress: onProgress
                ) {
                    session.recordCompletedPreview(child, parentURL: url)
                    measuredDirectItems += 1
                    total = addingWithoutOverflow(total, child.size)
                    totalItems = addingWithoutOverflow(totalItems, child.itemCount)
                    retainedChildren.insert(
                        RetainedNodeCandidate(
                            node: child,
                            isPriority: session.shouldPrioritize(entryURL)
                        )
                    )
                }
            }

            for try await child in group {
                pendingTaskCount -= 1
                guard let child else { continue }
                session.recordCompletedPreview(child, parentURL: url)
                measuredDirectItems += 1
                total = addingWithoutOverflow(total, child.size)
                totalItems = addingWithoutOverflow(totalItems, child.itemCount)
                let childURL = url.appendingPathComponent(child.name)
                retainedChildren.insert(
                    RetainedNodeCandidate(
                        node: child,
                        isPriority: session.shouldPrioritize(childURL)
                    )
                )
            }
        }

        session.diagnostics.recordNodeDecisions(
            retained: retainedChildren.retainedNodes.count,
            discarded: retainedChildren.discardedDirectItems
        )

        var children = retainedChildren.retainedNodes.map { $0.makeNode() }
        if retainedChildren.discardedDirectItems > 0 {
            children.append(
                FileNodeSnapshot(
                    name: "Smaller items",
                    size: retainedChildren.discardedSize,
                    isDirectory: false,
                    isReadable: true,
                    children: [],
                    itemCount: retainedChildren.discardedItemCount,
                    directItemCount: 0,
                    isAggregate: true
                )
            )
        }
        children.sort {
            RetainedNodeCandidate.isPreferred(
                RetainedNodeCandidate(node: $0),
                over: RetainedNodeCandidate(node: $1)
            )
        }

        return FileNodeSnapshot(
            name: name,
            size: total,
            isDirectory: true,
            isReadable: true,
            children: children,
            itemCount: totalItems,
            directItemCount: measuredDirectItems,
            isAggregate: false
        )
    }

    private static func inspectIsolatedSubtree(
        _ url: URL,
        session: ScanSession,
        ownsWorkerPermit: Bool,
        onProgress: @escaping ProgressHandler
    ) async throws -> FileNodeSnapshot? {
        let signposter = SpaceLensSignposts.providerSubtree
        let signpostID = signposter.makeSignpostID()
        let signpostState = signposter.beginInterval(
            "IsolatedSubtree",
            id: signpostID,
            "timeoutMilliseconds=\(Int(session.configuration.stalledSubtreeTimeout * 1_000))"
        )
        defer {
            signposter.endInterval("IsolatedSubtree", signpostState)
        }

        let monitor = ScanActivityMonitor()

        let resultBox = LockedResultBox<FileNodeSnapshot?>()
        session.diagnostics.recordDirectoryTask()
        let isolatedWorker = Task.detached(priority: .userInitiated) {
            do {
                let node = try await inspect(
                    url,
                    knownMetadata: nil,
                    session: session,
                    activityMonitor: monitor,
                    isInsideIsolatedSubtree: true,
                    ownsWorkerPermit: ownsWorkerPermit,
                    onProgress: onProgress
                )
                resultBox.store(.success(node))
            } catch {
                resultBox.store(.failure(error))
            }
        }

        while !resultBox.hasResult {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                _ = monitor.abandon()
                isolatedWorker.cancel()
                throw error
            }
            if resultBox.hasResult { break }

            do {
                try Task.checkCancellation()
            } catch {
                _ = monitor.abandon()
                isolatedWorker.cancel()
                throw error
            }

            if monitor.inactiveDuration >= session.configuration.stalledSubtreeTimeout {
                let abandonment = monitor.abandon()
                isolatedWorker.cancel()
                session.diagnostics.recordProviderTimeoutAndAbandonedWorker()
                signposter.emitEvent("SubtreeTimedOut", id: signpostID)

                session.mergeItems(
                    abandonment.pendingItems,
                    path: { url.path },
                    onProgress: onProgress
                )
                if !abandonment.recordedAnyItems {
                    _ = session.recordItem(
                        at: url,
                        activityMonitor: nil,
                        onProgress: onProgress
                    )
                    _ = session.recordObservation(
                        ScannedFileItem.unreadable(at: url, kind: .directory),
                        activityMonitor: nil
                    )
                    session.diagnostics.recordDirectory()
                }
                session.recordUnreadable(
                    at: url,
                    unresponsive: true,
                    forceProgressEmission: true,
                    onProgress: onProgress
                )

                return FileNodeSnapshot(
                    name: displayName(for: url),
                    size: 0,
                    isDirectory: true,
                    isReadable: false,
                    children: []
                )
            }
        }

        let abandonment = monitor.abandon()
        session.mergeItems(
            abandonment.pendingItems,
            path: { url.path },
            onProgress: onProgress
        )
        let result = try resultBox.take().get()
        if let result {
            session.mergeMappedBytes(result.size, itemCount: result.itemCount, within: url)
        }
        return result
    }

    private static func shouldIsolateProtectedSubtree(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/Library/Containers/")
            || path.contains("/Library/Group Containers/")
            || path.hasSuffix("/Library/Mobile Documents")
            || path.contains("/Library/Mobile Documents/")
            || path.hasSuffix("/Library/CloudStorage")
            || path.contains("/Library/CloudStorage/")
    }

    private static func currentResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    private static func addingWithoutOverflow(_ left: Int64, _ right: Int64) -> Int64 {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? Int64.max : result.partialValue
    }

    private static func addingWithoutOverflow(_ left: Int, _ right: Int) -> Int {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? Int.max : result.partialValue
    }

    private static func displayName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}

struct ScannedFileItem: Sendable {
    let url: URL
    let kind: LowLevelFileKind
    let size: Int64
    let identity: FileIdentity?
    let isReadable: Bool
    let modificationDate: Date?

    init(url: URL, metadata: LowLevelFileMetadata) {
        self.url = url.standardizedFileURL
        kind = metadata.kind
        size = metadata.isReadable && metadata.kind != .directory ? metadata.size : 0
        identity = metadata.identity
        isReadable = metadata.isReadable
        modificationDate = metadata.modificationDate
    }

    static func unreadable(
        at url: URL,
        kind: LowLevelFileKind = .other
    ) -> Self {
        Self(
            url: url.standardizedFileURL,
            kind: kind,
            size: 0,
            identity: nil,
            isReadable: false,
            modificationDate: nil
        )
    }

    private init(
        url: URL,
        kind: LowLevelFileKind,
        size: Int64,
        identity: FileIdentity?,
        isReadable: Bool,
        modificationDate: Date?
    ) {
        self.url = url
        self.kind = kind
        self.size = size
        self.identity = identity
        self.isReadable = isReadable
        self.modificationDate = modificationDate
    }
}

private final class DirectoryDiscoveryLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private let rootDepth: Int
    private let budget: DirectoryDiscoveryBudget
    private let deadline: Date
    private var observedDirectories = 0
    private var reachedLimit = false

    init(rootURL: URL, budget: DirectoryDiscoveryBudget) {
        rootDepth = rootURL.standardizedFileURL.pathComponents.count
        self.budget = budget
        deadline = Date().addingTimeInterval(budget.maximumDuration)
    }

    func shouldPrune(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        observedDirectories += 1
        let depth = max(url.standardizedFileURL.pathComponents.count - rootDepth, 0)
        if depth > budget.maximumDepth
            || observedDirectories > budget.maximumDirectories
            || Date() >= deadline {
            reachedLimit = true
            return true
        }
        return false
    }

    var wasTruncated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachedLimit
    }
}

private final class ScanSession: @unchecked Sendable {
    private static let completedPreviewChildLimit = 8
    private static let progressEmissionIntervalNanoseconds: UInt64 = 200_000_000

    private struct PreviewBranch {
        let name: String
        var size: Int64
        var itemCount: Int
        var completedSnapshot: FileNodeSnapshot?
    }

    let scope: ScanScope
    let configuration: ScannerConfiguration
    let visitedDirectories = VisitedDirectoryRegistry()
    let parallelism: ScanParallelismLimiter
    let directoryBuffers: BulkDirectoryBufferPool
    let diagnostics = ScanDiagnosticCounters()

    private let progressLock = NSLock()
    private let rootURL: URL
    private let rootName: String
    private let priorityPaths: Set<String>
    private let pruningDirectoryNames: Set<String>
    private let discoveryLimiter: DirectoryDiscoveryLimiter?
    private let itemHandler: DiskScanner.ItemHandler?
    private var progress: ScanProgress
    private var lastProgressEmission: UInt64 = 0
    private var previewBranches: [String: PreviewBranch] = [:]
    private var ungroupedPreviewSize: Int64 = 0
    private var ungroupedPreviewItems = 0

    init(
        progress: ScanProgress,
        rootURL: URL,
        rootName: String,
        scope: ScanScope,
        configuration: ScannerConfiguration,
        priorityPaths: Set<String>,
        pruningDirectoryNames: Set<String>,
        discoveryLimiter: DirectoryDiscoveryLimiter?,
        itemHandler: DiskScanner.ItemHandler?
    ) {
        self.progress = progress
        self.rootURL = rootURL
        self.rootName = rootName
        self.scope = scope
        self.configuration = configuration
        self.priorityPaths = priorityPaths
        self.pruningDirectoryNames = pruningDirectoryNames
        self.discoveryLimiter = discoveryLimiter
        self.itemHandler = itemHandler
        parallelism = ScanParallelismLimiter(
            permitCount: configuration.maximumParallelism
        )
        directoryBuffers = BulkDirectoryBufferPool(
            capacity: configuration.maximumParallelism,
            bufferSize: configuration.directoryBufferSize
        )
    }

    func shouldPrioritize(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return priorityPaths.contains { priorityPath in
            priorityPath == path || priorityPath.hasPrefix(path == "/" ? "/" : path + "/")
        }
    }

    func shouldPruneDirectory(at url: URL) -> Bool {
        if discoveryLimiter?.shouldPrune(url) == true { return true }
        return url.standardizedFileURL.path != rootURL.path
            && pruningDirectoryNames.contains(url.lastPathComponent)
    }

    @discardableResult
    func recordObservation(
        _ item: ScannedFileItem,
        activityMonitor: ScanActivityMonitor?
    ) -> Bool {
        guard let itemHandler else { return activityMonitor?.isActive != false }
        if let activityMonitor {
            return activityMonitor.performIfActive {
                itemHandler(item)
            }
        }
        itemHandler(item)
        return true
    }

    func progressSnapshot(at url: URL) -> ScanProgress {
        progressLock.lock()
        defer { progressLock.unlock() }
        progress.currentPath = url.path
        progress.previewRoot = makePreviewRoot()
        return progress
    }

    func diagnosticSnapshot() -> ScanDiagnosticSnapshot {
        diagnostics.snapshot(bufferAllocations: directoryBuffers.allocationCount)
    }

    func recordProgressEmission() {
        diagnostics.recordProgressEmission()
    }

    @discardableResult
    func recordItem(
        at url: URL,
        activityMonitor: ScanActivityMonitor?,
        onProgress: DiskScanner.ProgressHandler
    ) -> Bool {
        recordItem(
            path: { url.path },
            activityMonitor: activityMonitor,
            onProgress: onProgress
        )
    }

    @discardableResult
    func recordItem(
        path: () -> String,
        activityMonitor: ScanActivityMonitor?,
        onProgress: DiskScanner.ProgressHandler
    ) -> Bool {
        let itemCount: Int
        if let activityMonitor {
            guard activityMonitor.recordActivity() else { return false }
            itemCount = activityMonitor.takePendingItems()
        } else {
            itemCount = 1
        }

        mergeItems(itemCount, path: path, onProgress: onProgress)
        return true
    }

    func mergeItems(
        _ itemCount: Int,
        path: () -> String,
        onProgress: DiskScanner.ProgressHandler
    ) {
        guard itemCount > 0 else { return }

        progressLock.lock()
        diagnostics.recordProgressMerge()
        let addition = progress.itemsScanned.addingReportingOverflow(itemCount)
        progress.itemsScanned = addition.overflow ? Int.max : addition.partialValue

        let now = DispatchTime.now().uptimeNanoseconds
        let emittedProgress: ScanProgress?
        if progress.itemsScanned == 1
            || now &- lastProgressEmission >= Self.progressEmissionIntervalNanoseconds {
            lastProgressEmission = now
            progress.currentPath = path()
            progress.previewRoot = makePreviewRoot()
            emittedProgress = progress
        } else {
            emittedProgress = nil
        }
        progressLock.unlock()

        if let emittedProgress {
            diagnostics.recordProgressEmission()
            onProgress(emittedProgress)
        }
    }

    func mergeMappedBytes(_ bytes: Int64, itemCount: Int, within directoryURL: URL) {
        guard bytes > 0 else { return }

        progressLock.lock()
        progress.mappedBytes = addingWithoutOverflow(progress.mappedBytes, bytes)

        if let branchName = rootBranchName(containing: directoryURL) {
            if var branch = previewBranches[branchName] {
                branch.size = addingWithoutOverflow(branch.size, bytes)
                branch.itemCount = addingWithoutOverflow(branch.itemCount, itemCount)
                previewBranches[branchName] = branch
            } else if previewBranches.count < Self.completedPreviewChildLimit {
                previewBranches[branchName] = PreviewBranch(
                    name: branchName,
                    size: bytes,
                    itemCount: itemCount,
                    completedSnapshot: nil
                )
            } else {
                ungroupedPreviewSize = addingWithoutOverflow(ungroupedPreviewSize, bytes)
                ungroupedPreviewItems = addingWithoutOverflow(ungroupedPreviewItems, itemCount)
            }
        } else {
            ungroupedPreviewSize = addingWithoutOverflow(ungroupedPreviewSize, bytes)
            ungroupedPreviewItems = addingWithoutOverflow(ungroupedPreviewItems, itemCount)
        }
        progressLock.unlock()
    }

    func recordCompletedPreview(_ snapshot: FileNodeSnapshot, parentURL: URL) {
        guard parentURL.standardizedFileURL.path == rootURL.path else { return }

        progressLock.lock()
        if var branch = previewBranches[snapshot.name] {
            branch.completedSnapshot = projectedPreview(snapshot, remainingDepth: 1)
            branch.size = max(branch.size, snapshot.size)
            branch.itemCount = max(branch.itemCount, snapshot.itemCount)
            previewBranches[snapshot.name] = branch
        } else if previewBranches.count < Self.completedPreviewChildLimit {
            previewBranches[snapshot.name] = PreviewBranch(
                name: snapshot.name,
                size: snapshot.size,
                itemCount: snapshot.itemCount,
                completedSnapshot: projectedPreview(snapshot, remainingDepth: 1)
            )
        }
        progressLock.unlock()
    }

    func recordUnreadable(
        at url: URL,
        unresponsive: Bool,
        forceProgressEmission: Bool = false,
        onProgress: DiskScanner.ProgressHandler
    ) {
        recordUnreadable(
            path: { url.path },
            unresponsive: unresponsive,
            forceProgressEmission: forceProgressEmission,
            onProgress: onProgress
        )
    }

    func recordUnreadable(
        path: () -> String,
        unresponsive: Bool,
        forceProgressEmission: Bool = false,
        onProgress: DiskScanner.ProgressHandler
    ) {
        progressLock.lock()
        progress.unreadableItems += 1
        if unresponsive {
            progress.unresponsiveItems += 1
        }
        if forceProgressEmission {
            progress.currentPath = path()
            progress.previewRoot = makePreviewRoot()
        }
        let emittedProgress = forceProgressEmission ? progress : nil
        progressLock.unlock()

        if let emittedProgress {
            diagnostics.recordProgressEmission()
            onProgress(emittedProgress)
        }
    }

    private func rootBranchName(containing directoryURL: URL) -> String? {
        let directoryPath = directoryURL.standardizedFileURL.path
        let rootPath = rootURL.path
        guard directoryPath != rootPath else { return nil }

        let relativeStart = rootPath == "/" ? 1 : rootPath.count + 1
        guard directoryPath.count >= relativeStart else { return nil }
        let relative = String(directoryPath.dropFirst(relativeStart))
        return relative.split(separator: "/", maxSplits: 1).first.map(String.init)
    }

    private func makePreviewRoot() -> FileNode {
        var children = previewBranches.values.map { branch in
            if let completed = branch.completedSnapshot {
                return completed
            }
            return FileNodeSnapshot(
                name: branch.name,
                size: branch.size,
                isDirectory: true,
                isReadable: true,
                children: [],
                itemCount: max(branch.itemCount, 1),
                directItemCount: 0,
                isAggregate: false
            )
        }
        if ungroupedPreviewSize > 0 || ungroupedPreviewItems > 0 {
            children.append(
                FileNodeSnapshot(
                    name: "Smaller items",
                    size: ungroupedPreviewSize,
                    isDirectory: false,
                    isReadable: true,
                    children: [],
                    itemCount: max(ungroupedPreviewItems, 1),
                    directItemCount: 0,
                    isAggregate: true
                )
            )
        }
        children.sort { left, right in
            RetainedNodeCandidate.isPreferred(
                RetainedNodeCandidate(node: left),
                over: RetainedNodeCandidate(node: right)
            )
        }

        return FileNode(
            rootURL: rootURL,
            snapshot: FileNodeSnapshot(
                name: rootName,
                size: progress.mappedBytes,
                isDirectory: true,
                isReadable: true,
                children: children,
                itemCount: max(progress.itemsScanned, 1),
                directItemCount: children.count,
                isAggregate: false
            )
        )
    }

    private func projectedPreview(
        _ snapshot: FileNodeSnapshot,
        remainingDepth: Int
    ) -> FileNodeSnapshot {
        guard remainingDepth > 0, !snapshot.children.isEmpty else {
            return FileNodeSnapshot(
                name: snapshot.name,
                size: snapshot.size,
                isDirectory: snapshot.isDirectory,
                isReadable: snapshot.isReadable,
                children: [],
                itemCount: snapshot.itemCount,
                directItemCount: snapshot.directItemCount,
                isAggregate: snapshot.isAggregate
            )
        }

        let ordinaryChildren = snapshot.children.filter { !$0.isAggregate }
        let retained = ordinaryChildren.prefix(Self.completedPreviewChildLimit)
        let discarded = snapshot.children.filter { child in
            child.isAggregate || !retained.contains(where: { $0.name == child.name })
        }
        var children = retained.map {
            projectedPreview($0, remainingDepth: remainingDepth - 1)
        }
        let discardedSize = discarded.reduce(Int64(0)) {
            addingWithoutOverflow($0, $1.size)
        }
        let discardedItems = discarded.reduce(0) {
            addingWithoutOverflow($0, $1.itemCount)
        }
        if discardedSize > 0 || discardedItems > 0 {
            children.append(
                FileNodeSnapshot(
                    name: "Smaller items",
                    size: discardedSize,
                    isDirectory: false,
                    isReadable: true,
                    children: [],
                    itemCount: max(discardedItems, 1),
                    directItemCount: 0,
                    isAggregate: true
                )
            )
        }

        return FileNodeSnapshot(
            name: snapshot.name,
            size: snapshot.size,
            isDirectory: snapshot.isDirectory,
            isReadable: snapshot.isReadable,
            children: children,
            itemCount: snapshot.itemCount,
            directItemCount: snapshot.directItemCount,
            isAggregate: snapshot.isAggregate
        )
    }

    private func addingWithoutOverflow(_ left: Int64, _ right: Int64) -> Int64 {
        let addition = left.addingReportingOverflow(right)
        return addition.overflow ? Int64.max : addition.partialValue
    }

    private func addingWithoutOverflow(_ left: Int, _ right: Int) -> Int {
        let addition = left.addingReportingOverflow(right)
        return addition.overflow ? Int.max : addition.partialValue
    }
}

private struct ScanProgressBatch {
    private static let itemLimit = 256

    let session: ScanSession
    let activityMonitor: ScanActivityMonitor?
    let previewURL: URL
    let onProgress: DiskScanner.ProgressHandler
    private var localPendingItems = 0
    private var itemsSinceMerge = 0
    private var mappedBytesSinceMerge: Int64 = 0

    init(
        session: ScanSession,
        activityMonitor: ScanActivityMonitor?,
        previewURL: URL,
        onProgress: @escaping DiskScanner.ProgressHandler
    ) {
        self.session = session
        self.activityMonitor = activityMonitor
        self.previewURL = previewURL
        self.onProgress = onProgress
    }

    mutating func recordItem(size: Int64, path: () -> String) -> Bool {
        if let activityMonitor {
            guard activityMonitor.recordActivity() else { return false }
        } else {
            localPendingItems += 1
            let addition = mappedBytesSinceMerge.addingReportingOverflow(size)
            mappedBytesSinceMerge = addition.overflow ? Int64.max : addition.partialValue
        }
        itemsSinceMerge += 1

        if itemsSinceMerge >= Self.itemLimit {
            flush(path: path)
        }
        return true
    }

    mutating func flush(path: () -> String) {
        let itemCount: Int
        if let activityMonitor {
            itemCount = activityMonitor.takePendingItems()
        } else {
            itemCount = localPendingItems
            localPendingItems = 0
        }
        itemsSinceMerge = 0
        let mappedBytes = mappedBytesSinceMerge
        mappedBytesSinceMerge = 0
        if activityMonitor == nil {
            session.mergeMappedBytes(mappedBytes, itemCount: itemCount, within: previewURL)
        }
        session.mergeItems(itemCount, path: path, onProgress: onProgress)
    }
}

private final class ScanParallelismLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var availablePermits: Int

    init(permitCount: Int) {
        availablePermits = permitCount
    }

    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard availablePermits > 0 else { return false }
        availablePermits -= 1
        return true
    }

    func release() {
        lock.lock()
        availablePermits += 1
        lock.unlock()
    }
}

private final class VisitedDirectoryRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var identities: Set<FileIdentity> = []

    func insertIfNew(_ identity: FileIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return identities.insert(identity).inserted
    }
}

private struct ScannerConfiguration: @unchecked Sendable {
    let maximumParallelism: Int
    let directoryBufferSize: Int
    let stalledSubtreeTimeout: TimeInterval
    let shouldIsolateSubtree: DiskScanner.SubtreeIsolationPredicate
    let directoryReader: DiskScanner.DirectoryReader?
    let excludedPaths: Set<String>
}

private final class ScanActivityMonitor: @unchecked Sendable {
    struct Abandonment {
        let recordedAnyItems: Bool
        let pendingItems: Int
    }

    private let lock = NSLock()
    private var lastActivity = DispatchTime.now().uptimeNanoseconds
    private var hasRecordedItems = false
    private var pendingItems = 0
    private var isAbandoned = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isAbandoned
    }

    var inactiveDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = DispatchTime.now().uptimeNanoseconds &- lastActivity
        return TimeInterval(elapsed) / 1_000_000_000
    }

    func recordActivity() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isAbandoned else { return false }
        lastActivity = DispatchTime.now().uptimeNanoseconds
        hasRecordedItems = true
        let addition = pendingItems.addingReportingOverflow(1)
        pendingItems = addition.overflow ? Int.max : addition.partialValue
        return true
    }

    func performIfActive(_ body: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isAbandoned else { return false }
        body()
        return true
    }

    func takePendingItems() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let result = pendingItems
        pendingItems = 0
        return result
    }

    func abandon() -> Abandonment {
        lock.lock()
        defer { lock.unlock() }
        isAbandoned = true
        let result = Abandonment(
            recordedAnyItems: hasRecordedItems,
            pendingItems: pendingItems
        )
        pendingItems = 0
        return result
    }
}

private final class LockedResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    var hasResult: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func take() -> Result<Value, Error> {
        lock.lock()
        defer { lock.unlock() }
        return result ?? .failure(ScanFailure.cancelled)
    }
}

private struct RetainedNodeCandidate {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let isReadable: Bool
    let children: [FileNodeSnapshot]
    let itemCount: Int
    let directItemCount: Int
    let isAggregate: Bool
    let isPriority: Bool

    init(
        name: String,
        size: Int64,
        isDirectory: Bool,
        isReadable: Bool,
        isPriority: Bool = false
    ) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.isReadable = isReadable
        children = []
        itemCount = 1
        directItemCount = 0
        isAggregate = false
        self.isPriority = isPriority
    }

    init(node: FileNodeSnapshot, isPriority: Bool = false) {
        name = node.name
        size = node.size
        isDirectory = node.isDirectory
        isReadable = node.isReadable
        children = node.children
        itemCount = node.itemCount
        directItemCount = node.directItemCount
        isAggregate = node.isAggregate
        self.isPriority = isPriority
    }

    func makeNode() -> FileNodeSnapshot {
        FileNodeSnapshot(
            name: name,
            size: size,
            isDirectory: isDirectory,
            isReadable: isReadable,
            children: children,
            itemCount: itemCount,
            directItemCount: directItemCount,
            isAggregate: isAggregate
        )
    }

    static func isPreferred(_ left: Self, over right: Self) -> Bool {
        if left.isPriority != right.isPriority { return left.isPriority }
        if left.size != right.size { return left.size > right.size }
        if left.isDirectory != right.isDirectory { return left.isDirectory }
        return left.name < right.name
    }
}

private struct BoundedNodeAccumulator {
    let capacity: Int
    private var heap: [RetainedNodeCandidate] = []
    private(set) var discardedSize: Int64 = 0
    private(set) var discardedItemCount = 0
    private(set) var discardedDirectItems = 0

    init(capacity: Int) {
        self.capacity = capacity
    }

    var retainedNodes: [RetainedNodeCandidate] { heap }

    mutating func insert(_ node: RetainedNodeCandidate) {
        guard capacity > 0 else {
            discard(node)
            return
        }

        if heap.count < capacity {
            heap.append(node)
            siftUp(from: heap.count - 1)
            return
        }

        guard let leastPreferred = heap.first,
              RetainedNodeCandidate.isPreferred(node, over: leastPreferred) else {
            discard(node)
            return
        }

        heap[0] = node
        discard(leastPreferred)
        siftDown(from: 0)
    }

    private mutating func discard(_ node: RetainedNodeCandidate) {
        let sizeResult = discardedSize.addingReportingOverflow(node.size)
        discardedSize = sizeResult.overflow ? Int64.max : sizeResult.partialValue

        let countResult = discardedItemCount.addingReportingOverflow(node.itemCount)
        discardedItemCount = countResult.overflow ? Int.max : countResult.partialValue
        discardedDirectItems += 1
    }

    private mutating func siftUp(from start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard RetainedNodeCandidate.isPreferred(heap[parent], over: heap[child]) else { break }
            heap.swapAt(parent, child)
            child = parent
        }
    }

    private mutating func siftDown(from start: Int) {
        var parent = start
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var leastPreferred = left

            if right < heap.count,
               RetainedNodeCandidate.isPreferred(heap[left], over: heap[right]) {
                leastPreferred = right
            }

            guard RetainedNodeCandidate.isPreferred(
                heap[parent],
                over: heap[leastPreferred]
            ) else { return }
            heap.swapAt(parent, leastPreferred)
            parent = leastPreferred
        }
    }
}
