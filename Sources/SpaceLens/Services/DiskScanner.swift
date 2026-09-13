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

enum ScanPreviewPolicy: Equatable, Sendable {
    case live
    case countsOnly
}

struct DiskScanner: Sendable {
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
        excludedURLs: [URL] = [],
        traversalBudget: ScanTraversalBudget? = nil,
        previewPolicy: ScanPreviewPolicy = .live
    ) {
        let suggestedParallelism = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        let maximumParallelism = max(maximumParallelism ?? suggestedParallelism, 1)
        precondition(directoryBufferSize >= BulkDirectoryReader.minimumBufferSize)
        configuration = ScannerConfiguration(
            maximumParallelism: maximumParallelism,
            directoryBufferSize: directoryBufferSize,
            stalledSubtreeTimeout: stalledSubtreeTimeout,
            shouldIsolateSubtree: shouldIsolateSubtree ?? { url in
                Self.shouldIsolateProtectedSubtree(url)
            },
            directoryReader: directoryReader,
            excludedPaths: Set(excludedURLs.map { $0.standardizedFileURL.path }),
            traversalBudget: traversalBudget ?? ScanTraversalBudget(
                permitCount: maximumParallelism
            ),
            previewPolicy: previewPolicy
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
            try await configuration.traversalBudget.acquireRoot()
            defer { configuration.traversalBudget.release() }
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
                        "merges=\(diagnostics.progressMerges) emissions=\(diagnostics.progressEmissions) workerFlushes=\(diagnostics.workerProgressFlushes) forcedFlushes=\(diagnostics.forcedProgressFlushes) lockAcquisitions=\(diagnostics.progressLockAcquisitions)"
                    )
                    signposter.emitEvent(
                        "ScanPreviewCounters",
                        id: signpostID,
                        "byteMerges=\(diagnostics.previewMappedByteMerges) branchResolutions=\(diagnostics.rootPreviewBranchResolutions) completionAttempts=\(diagnostics.completedPreviewAttempts) completionAccepted=\(diagnostics.completedPreviewAccepted) constructions=\(diagnostics.previewConstructions) emissions=\(diagnostics.previewEmissions)"
                    )
                    signposter.emitEvent(
                        "ScanProgressLockTiming",
                        id: signpostID,
                        "waitNanoseconds=\(diagnostics.progressLockWaitNanoseconds) holdNanoseconds=\(diagnostics.progressLockHoldNanoseconds)"
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
            let rootProgress = ScanWorkerProgress(
                session: session,
                activityMonitor: nil,
                emitsInitialProgress: true,
                onProgress: onProgress
            )

            do {
                guard let root = try await Self.inspect(
                    standardizedURL,
                    knownMetadata: rootMetadata,
                    session: session,
                    activityMonitor: nil,
                    isInsideIsolatedSubtree: false,
                    ownsWorkerPermit: true,
                    traversalContext: .root,
                    workerProgress: rootProgress,
                    onProgress: onProgress
                ) else {
                    throw ScanFailure.inaccessible(standardizedURL)
                }
                try Task.checkCancellation()
                rootProgress.flushBeforeFinalSnapshot(path: { standardizedURL.path })
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
        traversalContext: ScanTraversalContext,
        workerProgress: ScanWorkerProgress,
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
            guard workerProgress.recordItem(
                size: 0,
                branch: traversalContext.previewBranch,
                path: { url.path }
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
            guard workerProgress.recordItem(
                size: 0,
                branch: traversalContext.previewBranch,
                path: { url.path }
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
            guard workerProgress.recordItem(
                size: metadata.size,
                branch: traversalContext.previewBranch,
                path: { url.path }
            ) else { throw CancellationError() }
            guard session.recordObservation(
                ScannedFileItem(url: url, metadata: metadata),
                activityMonitor: activityMonitor
            ) else { throw CancellationError() }
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
                traversalContext: traversalContext,
                workerProgress: workerProgress,
                onProgress: onProgress
            )
        }

        if let identity {
            guard session.visitedDirectories.insertIfNew(identity) else { return nil }
        }

        guard workerProgress.recordItem(
            size: 0,
            branch: traversalContext.previewBranch,
            path: { url.path }
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
                    guard workerProgress.recordItem(
                        size: 0,
                        branch: traversalContext.previewBranch,
                        path: { entryURL.path }
                    ) else {
                        throw CancellationError()
                    }
                    guard session.recordObservation(
                        ScannedFileItem.unreadable(at: entryURL),
                        activityMonitor: activityMonitor
                    ) else { throw CancellationError() }
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

            guard workerProgress.recordItem(
                size: entryMetadata.isReadable ? entryMetadata.size : 0,
                branch: traversalContext.previewBranch,
                path: { entry.url(relativeTo: url).path }
            ) else { throw CancellationError() }
            guard session.recordObservation(
                ScannedFileItem(
                    url: entry.url(relativeTo: url),
                    metadata: entryMetadata
                ),
                activityMonitor: activityMonitor
            ) else { throw CancellationError() }
            if !entryMetadata.isReadable {
                let entryURL = entry.url(relativeTo: url)
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
                    isPriority: session.shouldPrioritize(entry.url(relativeTo: url))
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            session.recordUnreadable(at: url, unresponsive: false, onProgress: onProgress)
            return FileNodeSnapshot(
                name: name,
                size: 0,
                isDirectory: true,
                isReadable: false,
                children: []
            )
        }

        try await withThrowingTaskGroup(of: ScanChildTaskResult.self) { group in
            var pendingTaskCount = 0

            for pendingDirectory in pendingDirectories {
                try Task.checkCancellation()
                guard activityMonitor?.isActive != false else { throw CancellationError() }
                let entry = pendingDirectory.entry
                let entryMetadata = pendingDirectory.metadata
                let entryURL = entry.url(relativeTo: url)
                let childPreviewBranch: RootPreviewBranch
                if traversalContext.isRoot, session.maintainsPreview {
                    workerProgress.recordRootBranchResolution()
                    childPreviewBranch = .named(entryMetadata.name)
                } else {
                    childPreviewBranch = traversalContext.previewBranch
                }
                let childTraversalContext = ScanTraversalContext(
                    isRoot: false,
                    previewBranch: childPreviewBranch
                )

                var acquiredPermit = session.parallelism.tryAcquireWorker()
                while !acquiredPermit, !ownsWorkerPermit, pendingTaskCount > 0 {
                    if let completedResult = try await group.next() {
                        pendingTaskCount -= 1
                        workerProgress.absorb(
                            completedResult.progressDelta,
                            path: { url.path }
                        )
                        if let completedChild = completedResult.node {
                            if traversalContext.isRoot {
                                workerProgress.recordCompletedPreview(
                                    completedChild,
                                    branch: .named(completedChild.name),
                                    path: { url.path }
                                )
                            }
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
                    acquiredPermit = session.parallelism.tryAcquireWorker()
                }

                if acquiredPermit {
                    pendingTaskCount += 1
                    session.diagnostics.recordDirectoryTask()
                    group.addTask {
                        let childProgress = ScanWorkerProgress(
                            session: session,
                            activityMonitor: activityMonitor,
                            emitsInitialProgress: false,
                            onProgress: onProgress
                        )
                        defer { session.parallelism.release() }
                        let node = try await inspect(
                            entryURL,
                            knownMetadata: entryMetadata,
                            session: session,
                            activityMonitor: activityMonitor,
                            isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                            ownsWorkerPermit: true,
                            traversalContext: childTraversalContext,
                            workerProgress: childProgress,
                            onProgress: onProgress
                        )
                        return ScanChildTaskResult(
                            node: node,
                            progressDelta: childProgress.takePendingDeltaForParent()
                        )
                    }
                } else if let child = try await inspect(
                    entryURL,
                    knownMetadata: entryMetadata,
                    session: session,
                    activityMonitor: activityMonitor,
                    isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                    ownsWorkerPermit: ownsWorkerPermit,
                    traversalContext: childTraversalContext,
                    workerProgress: workerProgress,
                    onProgress: onProgress
                ) {
                    if traversalContext.isRoot {
                        workerProgress.recordCompletedPreview(
                            child,
                            branch: childPreviewBranch,
                            path: { url.path }
                        )
                    }
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

            for try await completedResult in group {
                pendingTaskCount -= 1
                workerProgress.absorb(
                    completedResult.progressDelta,
                    path: { url.path }
                )
                guard let child = completedResult.node else { continue }
                if traversalContext.isRoot {
                    workerProgress.recordCompletedPreview(
                        child,
                        branch: .named(child.name),
                        path: { url.path }
                    )
                }
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
        traversalContext: ScanTraversalContext,
        workerProgress: ScanWorkerProgress,
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
            let isolatedProgress = ScanWorkerProgress(
                session: session,
                activityMonitor: monitor,
                emitsInitialProgress: false,
                onProgress: onProgress
            )
            do {
                let node = try await inspect(
                    url,
                    knownMetadata: nil,
                    session: session,
                    activityMonitor: monitor,
                    isInsideIsolatedSubtree: true,
                    ownsWorkerPermit: ownsWorkerPermit,
                    traversalContext: traversalContext,
                    workerProgress: isolatedProgress,
                    onProgress: onProgress
                )
                isolatedProgress.flushBeforeProviderCompletion(path: { url.path })
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

                session.mergeProgress(
                    ScanProgressDelta(itemCount: abandonment.pendingItems),
                    path: { url.path },
                    allowsEmission: true,
                    forced: true,
                    onProgress: onProgress
                )
                if !abandonment.recordedAnyItems {
                    _ = workerProgress.recordItem(
                        size: 0,
                        branch: traversalContext.previewBranch,
                        path: { url.path }
                    )
                    workerProgress.flushForWorkerCompletion(path: { url.path })
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
        session.mergeProgress(
            ScanProgressDelta(itemCount: abandonment.pendingItems),
            path: { url.path },
            allowsEmission: true,
            forced: true,
            onProgress: onProgress
        )
        let result = try resultBox.take().get()
        if let result {
            workerProgress.recordMappedBytes(
                result.size,
                itemCount: result.itemCount,
                branch: traversalContext.previewBranch,
                path: { url.path }
            )
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

private enum RootPreviewBranch: Hashable, Sendable {
    case ungrouped
    case named(String)
}

private struct ScanTraversalContext: Sendable {
    let isRoot: Bool
    let previewBranch: RootPreviewBranch

    static let root = Self(isRoot: true, previewBranch: .ungrouped)
}

private struct PreviewProgressDelta: Sendable {
    var bytes: Int64 = 0
    var itemCount = 0
}

private struct ScanProgressDelta: Sendable {
    var itemCount = 0
    var mappedBytes: Int64 = 0
    var previewByBranch: [RootPreviewBranch: PreviewProgressDelta] = [:]
    var completedPreviews: [RootPreviewBranch: FileNodeSnapshot] = [:]
    var rootBranchResolutions = 0
    var completedPreviewAttempts = 0

    var isEmpty: Bool {
        itemCount == 0
            && mappedBytes == 0
            && previewByBranch.isEmpty
            && completedPreviews.isEmpty
            && rootBranchResolutions == 0
            && completedPreviewAttempts == 0
    }
}

private struct ScanChildTaskResult: Sendable {
    let node: FileNodeSnapshot?
    let progressDelta: ScanProgressDelta
}

private final class ScanSession: @unchecked Sendable {
    fileprivate static let completedPreviewChildLimit = 8
    fileprivate static let progressEmissionIntervalNanoseconds: UInt64 = 200_000_000

    private struct PreviewBranch {
        let name: String
        var size: Int64
        var itemCount: Int
        var completedSnapshot: FileNodeSnapshot?
    }

    let scope: ScanScope
    let configuration: ScannerConfiguration
    let visitedDirectories = VisitedDirectoryRegistry()
    let parallelism: ScanTraversalBudget
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
    private var progressLockAcquisitions = 0
    private var progressLockWaitNanoseconds: UInt64 = 0
    private var progressLockHoldNanoseconds: UInt64 = 0
    private var previewMappedByteMerges = 0
    private var rootPreviewBranchResolutions = 0
    private var completedPreviewAttempts = 0
    private var completedPreviewAccepted = 0
    private var previewConstructions = 0
    private var previewEmissions = 0
    private var workerProgressFlushes = 0
    private var forcedProgressFlushes = 0

    var maintainsPreview: Bool {
        configuration.previewPolicy == .live
    }

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
        parallelism = configuration.traversalBudget
        directoryBuffers = BulkDirectoryBufferPool(
            capacity: configuration.maximumParallelism,
            bufferSize: configuration.directoryBufferSize,
            includeModificationDate: itemHandler != nil
        )
    }

    func shouldPrioritize(_ url: @autoclosure () -> URL) -> Bool {
        guard !priorityPaths.isEmpty else { return false }
        let path = url().standardizedFileURL.path
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
        _ item: @autoclosure () -> ScannedFileItem,
        activityMonitor: ScanActivityMonitor?
    ) -> Bool {
        guard let itemHandler else { return activityMonitor?.isActive != false }
        if let activityMonitor {
            return activityMonitor.performIfActive {
                itemHandler(item())
            }
        }
        itemHandler(item())
        return true
    }

    func mergeProgress(
        _ delta: ScanProgressDelta,
        path: () -> String,
        allowsEmission: Bool,
        forced: Bool,
        onProgress: DiskScanner.ProgressHandler
    ) {
        guard !delta.isEmpty else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        let lockStartedAt = now
        progressLock.lock()
        let lockAcquiredAt = DispatchTime.now().uptimeNanoseconds
        progressLockAcquisitions = addingWithoutOverflow(progressLockAcquisitions, 1)
        progressLockWaitNanoseconds = addingWithoutOverflow(
            progressLockWaitNanoseconds,
            lockAcquiredAt &- lockStartedAt
        )
        workerProgressFlushes = addingWithoutOverflow(workerProgressFlushes, 1)
        if forced {
            forcedProgressFlushes = addingWithoutOverflow(forcedProgressFlushes, 1)
        }
        diagnostics.recordProgressMerge()

        progress.itemsScanned = addingWithoutOverflow(progress.itemsScanned, delta.itemCount)
        progress.mappedBytes = addingWithoutOverflow(progress.mappedBytes, delta.mappedBytes)
        rootPreviewBranchResolutions = addingWithoutOverflow(
            rootPreviewBranchResolutions,
            delta.rootBranchResolutions
        )
        completedPreviewAttempts = addingWithoutOverflow(
            completedPreviewAttempts,
            delta.completedPreviewAttempts
        )

        if maintainsPreview {
            mergePreviewDeltas(delta.previewByBranch)
            mergeCompletedPreviews(delta.completedPreviews)
        }

        let emittedProgress: ScanProgress?
        if allowsEmission
            && (lastProgressEmission == 0
                || now &- lastProgressEmission >= Self.progressEmissionIntervalNanoseconds) {
            lastProgressEmission = now
            progress.currentPath = path()
            if maintainsPreview {
                previewConstructions = addingWithoutOverflow(previewConstructions, 1)
                previewEmissions = addingWithoutOverflow(previewEmissions, 1)
                progress.previewRoot = makePreviewRoot()
            } else {
                progress.previewRoot = nil
            }
            emittedProgress = progress
        } else {
            emittedProgress = nil
        }

        progressLockHoldNanoseconds = addingWithoutOverflow(
            progressLockHoldNanoseconds,
            DispatchTime.now().uptimeNanoseconds &- lockAcquiredAt
        )
        progressLock.unlock()

        if let emittedProgress {
            diagnostics.recordProgressEmission()
            onProgress(emittedProgress)
        }
    }

    func progressSnapshot(at url: URL) -> ScanProgress {
        let lockStartedAt = DispatchTime.now().uptimeNanoseconds
        progressLock.lock()
        let lockAcquiredAt = DispatchTime.now().uptimeNanoseconds
        progressLockAcquisitions = addingWithoutOverflow(progressLockAcquisitions, 1)
        progressLockWaitNanoseconds = addingWithoutOverflow(
            progressLockWaitNanoseconds,
            lockAcquiredAt &- lockStartedAt
        )
        progress.currentPath = url.path
        if maintainsPreview {
            previewConstructions = addingWithoutOverflow(previewConstructions, 1)
            previewEmissions = addingWithoutOverflow(previewEmissions, 1)
            progress.previewRoot = makePreviewRoot()
        } else {
            progress.previewRoot = nil
        }
        let snapshot = progress
        progressLockHoldNanoseconds = addingWithoutOverflow(
            progressLockHoldNanoseconds,
            DispatchTime.now().uptimeNanoseconds &- lockAcquiredAt
        )
        progressLock.unlock()
        return snapshot
    }

    func diagnosticSnapshot() -> ScanDiagnosticSnapshot {
        var snapshot = diagnostics.snapshot(bufferAllocations: directoryBuffers.allocationCount)
        progressLock.lock()
        snapshot.progressLockAcquisitions = progressLockAcquisitions
        snapshot.progressLockWaitNanoseconds = progressLockWaitNanoseconds
        snapshot.progressLockHoldNanoseconds = progressLockHoldNanoseconds
        snapshot.previewMappedByteMerges = previewMappedByteMerges
        snapshot.rootPreviewBranchResolutions = rootPreviewBranchResolutions
        snapshot.completedPreviewAttempts = completedPreviewAttempts
        snapshot.completedPreviewAccepted = completedPreviewAccepted
        snapshot.previewConstructions = previewConstructions
        snapshot.previewEmissions = previewEmissions
        snapshot.workerProgressFlushes = workerProgressFlushes
        snapshot.forcedProgressFlushes = forcedProgressFlushes
        progressLock.unlock()
        return snapshot
    }

    func recordProgressEmission() {
        diagnostics.recordProgressEmission()
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
        let lockStartedAt = DispatchTime.now().uptimeNanoseconds
        progressLock.lock()
        let lockAcquiredAt = DispatchTime.now().uptimeNanoseconds
        progressLockAcquisitions = addingWithoutOverflow(progressLockAcquisitions, 1)
        progressLockWaitNanoseconds = addingWithoutOverflow(
            progressLockWaitNanoseconds,
            lockAcquiredAt &- lockStartedAt
        )
        progress.unreadableItems = addingWithoutOverflow(progress.unreadableItems, 1)
        if unresponsive {
            progress.unresponsiveItems = addingWithoutOverflow(progress.unresponsiveItems, 1)
        }
        if forceProgressEmission {
            lastProgressEmission = DispatchTime.now().uptimeNanoseconds
            progress.currentPath = path()
            if maintainsPreview {
                previewConstructions = addingWithoutOverflow(previewConstructions, 1)
                previewEmissions = addingWithoutOverflow(previewEmissions, 1)
                progress.previewRoot = makePreviewRoot()
            } else {
                progress.previewRoot = nil
            }
        }
        let emittedProgress = forceProgressEmission ? progress : nil
        progressLockHoldNanoseconds = addingWithoutOverflow(
            progressLockHoldNanoseconds,
            DispatchTime.now().uptimeNanoseconds &- lockAcquiredAt
        )
        progressLock.unlock()

        if let emittedProgress {
            diagnostics.recordProgressEmission()
            onProgress(emittedProgress)
        }
    }

    private func mergePreviewDeltas(
        _ deltas: [RootPreviewBranch: PreviewProgressDelta]
    ) {
        for (rootBranch, delta) in deltas where delta.bytes > 0 {
            previewMappedByteMerges = addingWithoutOverflow(previewMappedByteMerges, 1)
            switch rootBranch {
            case .ungrouped:
                ungroupedPreviewSize = addingWithoutOverflow(ungroupedPreviewSize, delta.bytes)
                ungroupedPreviewItems = addingWithoutOverflow(
                    ungroupedPreviewItems,
                    delta.itemCount
                )
            case .named(let branchName):
                if var branch = previewBranches[branchName] {
                    branch.size = addingWithoutOverflow(branch.size, delta.bytes)
                    branch.itemCount = addingWithoutOverflow(branch.itemCount, delta.itemCount)
                    previewBranches[branchName] = branch
                } else if previewBranches.count < Self.completedPreviewChildLimit {
                    previewBranches[branchName] = PreviewBranch(
                        name: branchName,
                        size: delta.bytes,
                        itemCount: delta.itemCount,
                        completedSnapshot: nil
                    )
                } else {
                    ungroupedPreviewSize = addingWithoutOverflow(
                        ungroupedPreviewSize,
                        delta.bytes
                    )
                    ungroupedPreviewItems = addingWithoutOverflow(
                        ungroupedPreviewItems,
                        delta.itemCount
                    )
                }
            }
        }
    }

    private func mergeCompletedPreviews(
        _ completedPreviews: [RootPreviewBranch: FileNodeSnapshot]
    ) {
        for (rootBranch, snapshot) in completedPreviews {
            guard case .named(let branchName) = rootBranch else { continue }
            if var branch = previewBranches[branchName] {
                branch.completedSnapshot = snapshot
                branch.size = max(branch.size, snapshot.size)
                branch.itemCount = max(branch.itemCount, snapshot.itemCount)
                previewBranches[branchName] = branch
                completedPreviewAccepted = addingWithoutOverflow(completedPreviewAccepted, 1)
            } else if previewBranches.count < Self.completedPreviewChildLimit {
                previewBranches[branchName] = PreviewBranch(
                    name: branchName,
                    size: snapshot.size,
                    itemCount: snapshot.itemCount,
                    completedSnapshot: snapshot
                )
                completedPreviewAccepted = addingWithoutOverflow(completedPreviewAccepted, 1)
            }
        }
    }

    private func makePreviewRoot() -> FileNode {
        var children = previewBranches.values.map { branch in
            if let completed = branch.completedSnapshot {
                return projectedPreview(completed, remainingDepth: 1)
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

    private func addingWithoutOverflow(_ left: UInt64, _ right: UInt64) -> UInt64 {
        let addition = left.addingReportingOverflow(right)
        return addition.overflow ? UInt64.max : addition.partialValue
    }
}

private final class ScanWorkerProgress {
    private static let clockCheckItemLimit = 256

    private let session: ScanSession
    private let activityMonitor: ScanActivityMonitor?
    private let onProgress: DiskScanner.ProgressHandler
    private var delta = ScanProgressDelta()
    private var activePreviewBranch: RootPreviewBranch?
    private var activePreviewDelta = PreviewProgressDelta()
    private var itemsSinceClockCheck = 0
    private var lastMergeCheck = DispatchTime.now().uptimeNanoseconds
    private var emitsInitialProgress: Bool

    init(
        session: ScanSession,
        activityMonitor: ScanActivityMonitor?,
        emitsInitialProgress: Bool,
        onProgress: @escaping DiskScanner.ProgressHandler
    ) {
        self.session = session
        self.activityMonitor = activityMonitor
        self.emitsInitialProgress = emitsInitialProgress
        self.onProgress = onProgress
    }

    @discardableResult
    func recordItem(
        size: Int64,
        previewItemCount: Int = 1,
        branch: RootPreviewBranch,
        path: () -> String
    ) -> Bool {
        if let activityMonitor {
            guard activityMonitor.recordActivity() else { return false }
            itemsSinceClockCheck += 1
            if itemsSinceClockCheck >= Self.clockCheckItemLimit {
                itemsSinceClockCheck = 0
                flushProviderItemsIfDue(path: path)
            }
            return true
        }

        delta.itemCount = addingWithoutOverflow(delta.itemCount, 1)
        delta.mappedBytes = addingWithoutOverflow(delta.mappedBytes, size)
        recordPreviewBytes(size, itemCount: previewItemCount, branch: branch)
        itemsSinceClockCheck += 1

        if emitsInitialProgress {
            emitsInitialProgress = false
            flush(path: path, allowsEmission: true, forced: false)
        } else if itemsSinceClockCheck >= Self.clockCheckItemLimit {
            itemsSinceClockCheck = 0
            flushIfDue(path: path)
        }
        return true
    }

    func recordMappedBytes(
        _ bytes: Int64,
        itemCount: Int,
        branch: RootPreviewBranch,
        path: () -> String
    ) {
        guard activityMonitor == nil, bytes > 0 else { return }
        delta.mappedBytes = addingWithoutOverflow(delta.mappedBytes, bytes)
        recordPreviewBytes(bytes, itemCount: itemCount, branch: branch)
        flushIfDue(path: path)
    }

    func recordRootBranchResolution() {
        guard session.maintainsPreview else { return }
        delta.rootBranchResolutions = addingWithoutOverflow(delta.rootBranchResolutions, 1)
    }

    func recordCompletedPreview(
        _ snapshot: FileNodeSnapshot,
        branch: RootPreviewBranch,
        path: () -> String
    ) {
        guard session.maintainsPreview else { return }
        delta.completedPreviewAttempts = addingWithoutOverflow(
            delta.completedPreviewAttempts,
            1
        )
        if delta.completedPreviews[branch] != nil
            || delta.completedPreviews.count < ScanSession.completedPreviewChildLimit {
            delta.completedPreviews[branch] = snapshot
        }
        flushIfDue(path: path)
    }

    func flushForWorkerCompletion(path: () -> String) {
        guard activityMonitor == nil else { return }
        flush(path: path, allowsEmission: true, forced: true)
    }

    func takePendingDeltaForParent() -> ScanProgressDelta {
        guard activityMonitor == nil else { return ScanProgressDelta() }
        foldActivePreviewDelta()
        let pending = delta
        delta = ScanProgressDelta()
        itemsSinceClockCheck = 0
        return pending
    }

    func absorb(_ pending: ScanProgressDelta, path: () -> String) {
        guard activityMonitor == nil, !pending.isEmpty else { return }
        foldActivePreviewDelta()
        delta.itemCount = addingWithoutOverflow(delta.itemCount, pending.itemCount)
        delta.mappedBytes = addingWithoutOverflow(delta.mappedBytes, pending.mappedBytes)
        delta.rootBranchResolutions = addingWithoutOverflow(
            delta.rootBranchResolutions,
            pending.rootBranchResolutions
        )
        delta.completedPreviewAttempts = addingWithoutOverflow(
            delta.completedPreviewAttempts,
            pending.completedPreviewAttempts
        )
        for (branch, preview) in pending.previewByBranch {
            var accumulated = delta.previewByBranch[branch] ?? PreviewProgressDelta()
            accumulated.bytes = addingWithoutOverflow(accumulated.bytes, preview.bytes)
            accumulated.itemCount = addingWithoutOverflow(
                accumulated.itemCount,
                preview.itemCount
            )
            delta.previewByBranch[branch] = accumulated
        }
        for (branch, snapshot) in pending.completedPreviews
            where delta.completedPreviews[branch] != nil
                || delta.completedPreviews.count < ScanSession.completedPreviewChildLimit {
            delta.completedPreviews[branch] = snapshot
        }
        itemsSinceClockCheck = addingWithoutOverflow(
            itemsSinceClockCheck,
            pending.itemCount
        )
        flushIfDue(path: path)
    }

    func flushBeforeFinalSnapshot(path: () -> String) {
        guard activityMonitor == nil else { return }
        flush(path: path, allowsEmission: false, forced: true)
    }

    func flushBeforeProviderCompletion(path: () -> String) {
        guard let activityMonitor else { return }
        guard activityMonitor.isActive else {
            delta = ScanProgressDelta()
            return
        }
        flush(path: path, allowsEmission: true, forced: true)
    }

    private func flushProviderItemsIfDue(path: () -> String) {
        guard let activityMonitor else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now &- lastMergeCheck >= ScanSession.progressEmissionIntervalNanoseconds else {
            return
        }
        lastMergeCheck = now
        let itemCount = activityMonitor.takePendingItems()
        guard itemCount > 0 else { return }
        session.mergeProgress(
            ScanProgressDelta(itemCount: itemCount),
            path: path,
            allowsEmission: true,
            forced: false,
            onProgress: onProgress
        )
    }

    private func flushIfDue(path: () -> String) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now &- lastMergeCheck >= ScanSession.progressEmissionIntervalNanoseconds else {
            return
        }
        lastMergeCheck = now
        flush(path: path, allowsEmission: true, forced: false)
    }

    private func flush(
        path: () -> String,
        allowsEmission: Bool,
        forced: Bool
    ) {
        foldActivePreviewDelta()
        guard !delta.isEmpty else { return }
        let pending = delta
        delta = ScanProgressDelta()
        itemsSinceClockCheck = 0
        session.mergeProgress(
            pending,
            path: path,
            allowsEmission: allowsEmission,
            forced: forced,
            onProgress: onProgress
        )
    }

    private func recordPreviewBytes(
        _ bytes: Int64,
        itemCount: Int,
        branch: RootPreviewBranch
    ) {
        guard session.maintainsPreview, bytes > 0 else { return }
        if activePreviewBranch != branch {
            foldActivePreviewDelta()
            activePreviewBranch = branch
        }
        activePreviewDelta.bytes = addingWithoutOverflow(activePreviewDelta.bytes, bytes)
        activePreviewDelta.itemCount = addingWithoutOverflow(
            activePreviewDelta.itemCount,
            itemCount
        )
    }

    private func foldActivePreviewDelta() {
        guard let activePreviewBranch, activePreviewDelta.bytes > 0 else { return }
        var branchDelta = delta.previewByBranch[activePreviewBranch] ?? PreviewProgressDelta()
        branchDelta.bytes = addingWithoutOverflow(branchDelta.bytes, activePreviewDelta.bytes)
        branchDelta.itemCount = addingWithoutOverflow(
            branchDelta.itemCount,
            activePreviewDelta.itemCount
        )
        delta.previewByBranch[activePreviewBranch] = branchDelta
        self.activePreviewBranch = nil
        activePreviewDelta = PreviewProgressDelta()
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

final class ScanTraversalBudget: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let activeReaders: Int
        let maximumObservedReaders: Int
        let waitingRootReaders: Int
        let permitCount: Int
    }

    private let lock = NSLock()
    let permitCount: Int
    private var availablePermits: Int
    private var waitingRootReaders = 0
    private var maximumObservedReaders = 0
    private let activityObserver: (@Sendable (Int) -> Void)?

    init(
        permitCount: Int,
        activityObserver: (@Sendable (Int) -> Void)? = nil
    ) {
        precondition(permitCount > 0)
        self.permitCount = permitCount
        availablePermits = permitCount
        self.activityObserver = activityObserver
    }

    func acquireRoot() async throws {
        registerRootWaiter()

        do {
            while true {
                try Task.checkCancellation()
                if claimRootPermit() { return }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        } catch {
            unregisterRootWaiter()
            throw error
        }
    }

    func tryAcquireWorker() -> Bool {
        lock.lock()
        guard availablePermits > 0, waitingRootReaders == 0 else {
            lock.unlock()
            return false
        }
        let activeReaders = claimPermitWithoutLocking()
        lock.unlock()
        activityObserver?(activeReaders)
        return true
    }

    func release() {
        lock.lock()
        precondition(availablePermits < permitCount, "Released an unowned scan traversal permit")
        availablePermits += 1
        let activeReaders = permitCount - availablePermits
        lock.unlock()
        activityObserver?(activeReaders)
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            activeReaders: permitCount - availablePermits,
            maximumObservedReaders: maximumObservedReaders,
            waitingRootReaders: waitingRootReaders,
            permitCount: permitCount
        )
    }

    private func claimRootPermit() -> Bool {
        lock.lock()
        guard availablePermits > 0 else {
            lock.unlock()
            return false
        }
        waitingRootReaders -= 1
        let activeReaders = claimPermitWithoutLocking()
        lock.unlock()
        activityObserver?(activeReaders)
        return true
    }

    private func registerRootWaiter() {
        lock.lock()
        waitingRootReaders += 1
        lock.unlock()
    }

    private func unregisterRootWaiter() {
        lock.lock()
        waitingRootReaders -= 1
        lock.unlock()
    }

    private func claimPermitWithoutLocking() -> Int {
        availablePermits -= 1
        let activeReaders = permitCount - availablePermits
        maximumObservedReaders = max(maximumObservedReaders, activeReaders)
        return activeReaders
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
    let traversalBudget: ScanTraversalBudget
    let previewPolicy: ScanPreviewPolicy
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
