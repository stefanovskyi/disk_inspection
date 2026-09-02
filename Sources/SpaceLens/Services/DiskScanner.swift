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

struct DiskScanner {
    typealias ProgressHandler = @Sendable (ScanProgress) -> Void
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
                        "directoryTasks=\(diagnostics.directoryTasks) retained=\(diagnostics.retainedNodes) discarded=\(diagnostics.discardedNodes)"
                    )
                    signposter.emitEvent(
                        "ScanProgressCounters",
                        id: signpostID,
                        "emissions=\(diagnostics.progressEmissions)"
                    )
                }
                signposter.endInterval("Scan", signpostState)
            }

            let start = Date()
            let rootMetadata = try? LowLevelMetadataReader.metadata(at: standardizedURL)
            let session = ScanSession(
                progress: ScanProgress(currentPath: standardizedURL.path),
                scope: ScanScope(
                    rootPath: standardizedURL.path,
                    rootDevice: rootMetadata?.identity?.device,
                    excludedPaths: configuration.excludedPaths
                ),
                configuration: configuration
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
                return ScanResult(
                    root: root,
                    duration: Date().timeIntervalSince(start),
                    itemsScanned: progress.itemsScanned,
                    unreadableItems: progress.unreadableItems,
                    diagnostics: session.diagnosticSnapshot()
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
    ) async throws -> FileNode? {
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
            session.recordUnreadable(at: url, unresponsive: false, onProgress: onProgress)
            return FileNode(
                url: url,
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
            session.recordUnreadable(at: url, unresponsive: false, onProgress: onProgress)
            return FileNode(
                url: url,
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
            return FileNode(
                url: url,
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

        let entries: [LowLevelDirectoryEntry]
        do {
            if let directoryReader = session.configuration.directoryReader {
                let urls = try directoryReader(url, [])
                entries = urls.map {
                    session.diagnostics.recordFallbackLstat()
                    return LowLevelDirectoryEntry(
                        url: $0,
                        metadata: try? LowLevelMetadataReader.metadata(at: $0)
                    )
                }
            } else {
                entries = try BulkDirectoryReader.contents(
                    of: url,
                    using: session.directoryBuffers,
                    diagnostics: session.diagnostics
                )
            }
            try Task.checkCancellation()
            guard activityMonitor?.isActive != false else { throw CancellationError() }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            session.recordUnreadable(at: url, unresponsive: false, onProgress: onProgress)
            return FileNode(
                url: url,
                name: name,
                size: 0,
                isDirectory: true,
                isReadable: false,
                children: []
            )
        }

        var retainedChildren = BoundedNodeAccumulator(capacity: retainedChildLimit)
        var total: Int64 = 0
        var totalItems = 1
        var measuredDirectItems = 0

        try await withThrowingTaskGroup(of: FileNode?.self) { group in
            var pendingTaskCount = 0

            for entry in entries {
                try Task.checkCancellation()
                guard activityMonitor?.isActive != false else { throw CancellationError() }

                let entryMetadata: LowLevelFileMetadata
                if let metadata = entry.metadata {
                    entryMetadata = metadata
                } else {
                    do {
                        session.diagnostics.recordFallbackLstat()
                        entryMetadata = try LowLevelMetadataReader.metadata(at: entry.url)
                    } catch {
                        guard session.recordItem(
                            at: entry.url,
                            activityMonitor: activityMonitor,
                            onProgress: onProgress
                        ) else { throw CancellationError() }
                        session.recordUnreadable(
                            at: entry.url,
                            unresponsive: false,
                            onProgress: onProgress
                        )
                        measuredDirectItems += 1
                        totalItems = addingWithoutOverflow(totalItems, 1)
                        retainedChildren.insert(
                            RetainedNodeCandidate(
                                url: entry.url,
                                name: displayName(for: entry.url),
                                size: 0,
                                isDirectory: false,
                                isReadable: false
                            )
                        )
                        continue
                    }
                }

                guard entryMetadata.kind == .directory, entryMetadata.isReadable else {
                    guard session.recordItem(
                        at: entry.url,
                        activityMonitor: activityMonitor,
                        onProgress: onProgress
                    ) else { throw CancellationError() }
                    if !entryMetadata.isReadable {
                        session.recordUnreadable(
                            at: entry.url,
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
                            url: entry.url,
                            name: entryMetadata.name,
                            size: size,
                            isDirectory: entryMetadata.kind == .directory,
                            isReadable: entryMetadata.isReadable
                        )
                    )
                    continue
                }

                var acquiredPermit = session.parallelism.tryAcquire()
                while !acquiredPermit, !ownsWorkerPermit, pendingTaskCount > 0 {
                    if let completedChild = try await group.next() {
                        pendingTaskCount -= 1
                        if let completedChild {
                            measuredDirectItems += 1
                            total = addingWithoutOverflow(total, completedChild.size)
                            totalItems = addingWithoutOverflow(totalItems, completedChild.itemCount)
                            retainedChildren.insert(RetainedNodeCandidate(node: completedChild))
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
                            entry.url,
                            knownMetadata: entryMetadata,
                            session: session,
                            activityMonitor: activityMonitor,
                            isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                            ownsWorkerPermit: true,
                            onProgress: onProgress
                        )
                    }
                } else if let child = try await inspect(
                    entry.url,
                    knownMetadata: entryMetadata,
                    session: session,
                    activityMonitor: activityMonitor,
                    isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                    ownsWorkerPermit: ownsWorkerPermit,
                    onProgress: onProgress
                ) {
                    measuredDirectItems += 1
                    total = addingWithoutOverflow(total, child.size)
                    totalItems = addingWithoutOverflow(totalItems, child.itemCount)
                    retainedChildren.insert(RetainedNodeCandidate(node: child))
                }
            }

            for try await child in group {
                pendingTaskCount -= 1
                guard let child else { continue }
                measuredDirectItems += 1
                total = addingWithoutOverflow(total, child.size)
                totalItems = addingWithoutOverflow(totalItems, child.itemCount)
                retainedChildren.insert(RetainedNodeCandidate(node: child))
            }
        }

        session.diagnostics.recordNodeDecisions(
            retained: retainedChildren.retainedNodes.count,
            discarded: retainedChildren.discardedDirectItems
        )

        var children = retainedChildren.retainedNodes.map { $0.makeNode() }
        if retainedChildren.discardedDirectItems > 0 {
            children.append(
                FileNode(
                    url: url,
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

        return FileNode(
            url: url,
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
    ) async throws -> FileNode? {
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

        let resultBox = LockedResultBox<FileNode?>()
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
                monitor.abandon()
                isolatedWorker.cancel()
                throw error
            }
            if resultBox.hasResult { break }

            do {
                try Task.checkCancellation()
            } catch {
                monitor.abandon()
                isolatedWorker.cancel()
                throw error
            }

            if monitor.inactiveDuration >= session.configuration.stalledSubtreeTimeout {
                let recordedAnyItems = monitor.abandon()
                isolatedWorker.cancel()
                signposter.emitEvent("SubtreeTimedOut", id: signpostID)

                if !recordedAnyItems {
                    _ = session.recordItem(
                        at: url,
                        activityMonitor: nil,
                        onProgress: onProgress
                    )
                }
                session.recordUnreadable(
                    at: url,
                    unresponsive: true,
                    forceProgressEmission: true,
                    onProgress: onProgress
                )

                return FileNode(
                    url: url,
                    name: displayName(for: url),
                    size: 0,
                    isDirectory: true,
                    isReadable: false,
                    children: []
                )
            }
        }

        monitor.abandon()
        return try resultBox.take().get()
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

private final class ScanSession: @unchecked Sendable {
    let scope: ScanScope
    let configuration: ScannerConfiguration
    let visitedDirectories = VisitedDirectoryRegistry()
    let parallelism: ScanParallelismLimiter
    let directoryBuffers: BulkDirectoryBufferPool
    let diagnostics = ScanDiagnosticCounters()

    private let progressLock = NSLock()
    private var progress: ScanProgress
    private var lastProgressEmission: UInt64 = 0

    init(progress: ScanProgress, scope: ScanScope, configuration: ScannerConfiguration) {
        self.progress = progress
        self.scope = scope
        self.configuration = configuration
        parallelism = ScanParallelismLimiter(
            permitCount: configuration.maximumParallelism
        )
        directoryBuffers = BulkDirectoryBufferPool(
            capacity: configuration.maximumParallelism,
            bufferSize: configuration.directoryBufferSize
        )
    }

    func progressSnapshot(at url: URL) -> ScanProgress {
        progressLock.lock()
        defer { progressLock.unlock() }
        progress.currentPath = url.path
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
        if let activityMonitor, !activityMonitor.recordActivity() {
            return false
        }

        progressLock.lock()
        progress.itemsScanned += 1

        let now = DispatchTime.now().uptimeNanoseconds
        let emittedProgress: ScanProgress?
        if progress.itemsScanned == 1 || now &- lastProgressEmission >= 100_000_000 {
            lastProgressEmission = now
            progress.currentPath = url.path
            emittedProgress = progress
        } else {
            emittedProgress = nil
        }
        progressLock.unlock()

        if let emittedProgress {
            diagnostics.recordProgressEmission()
            onProgress(emittedProgress)
        }
        return true
    }

    func recordUnreadable(
        at url: URL,
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
            progress.currentPath = url.path
        }
        let emittedProgress = forceProgressEmission ? progress : nil
        progressLock.unlock()

        if let emittedProgress {
            diagnostics.recordProgressEmission()
            onProgress(emittedProgress)
        }
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
    private let lock = NSLock()
    private var lastActivity = DispatchTime.now().uptimeNanoseconds
    private var hasRecordedItems = false
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
        return true
    }

    @discardableResult
    func abandon() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        isAbandoned = true
        return hasRecordedItems
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
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let isReadable: Bool
    let children: [FileNode]
    let itemCount: Int
    let directItemCount: Int
    let isAggregate: Bool

    init(
        url: URL,
        name: String,
        size: Int64,
        isDirectory: Bool,
        isReadable: Bool
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.isReadable = isReadable
        children = []
        itemCount = 1
        directItemCount = 0
        isAggregate = false
    }

    init(node: FileNode) {
        url = node.url
        name = node.name
        size = node.size
        isDirectory = node.isDirectory
        isReadable = node.isReadable
        children = node.children
        itemCount = node.itemCount
        directItemCount = node.directItemCount
        isAggregate = node.isAggregate
    }

    func makeNode() -> FileNode {
        FileNode(
            url: url,
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
