import Foundation
import Darwin

struct FileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct ScanScope: Sendable {
    let rootPath: String
    let rootDevice: UInt64?

    private static let logicalRootExclusions = [
        "/.vol",
        "/dev",
        "/home",
        "/net",
        "/Network",
        "/System/Volumes",
        "/Volumes"
    ]

    func allows(_ url: URL, identity: FileIdentity?) -> Bool {
        let path = url.standardizedFileURL.path
        if path == rootPath { return true }

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

    private static let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey
    ]

    init(
        maximumParallelism: Int? = nil,
        stalledSubtreeTimeout: TimeInterval = 5,
        shouldIsolateSubtree: SubtreeIsolationPredicate? = nil,
        directoryReader: DirectoryReader? = nil
    ) {
        let suggestedParallelism = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        configuration = ScannerConfiguration(
            maximumParallelism: max(maximumParallelism ?? suggestedParallelism, 1),
            stalledSubtreeTimeout: stalledSubtreeTimeout,
            shouldIsolateSubtree: shouldIsolateSubtree ?? { url in
                Self.shouldIsolateProtectedSubtree(url)
            },
            directoryReader: directoryReader ?? { url, keys in
                try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            }
        )
    }

    func scan(
        url: URL,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async throws -> ScanResult {
        let configuration = configuration
        let worker = Task.detached(priority: .userInitiated) {
            let start = Date()
            let rootIdentity = Self.fileIdentity(for: url)
            let session = ScanSession(
                progress: ScanProgress(currentPath: url.path),
                scope: ScanScope(
                    rootPath: url.standardizedFileURL.path,
                    rootDevice: rootIdentity?.device
                ),
                configuration: configuration
            )

            do {
                guard let root = try await Self.inspect(
                    url,
                    session: session,
                    activityMonitor: nil,
                    isInsideIsolatedSubtree: false,
                    ownsWorkerPermit: false,
                    onProgress: onProgress
                ) else {
                    throw ScanFailure.inaccessible(url)
                }
                try Task.checkCancellation()
                let progress = session.progressSnapshot
                onProgress(progress)
                return ScanResult(
                    root: root,
                    duration: Date().timeIntervalSince(start),
                    itemsScanned: progress.itemsScanned,
                    unreadableItems: progress.unreadableItems
                )
            } catch is CancellationError {
                throw ScanFailure.cancelled
            } catch let failure as ScanFailure {
                throw failure
            } catch {
                throw ScanFailure.inaccessible(url)
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
        session: ScanSession,
        activityMonitor: ScanActivityMonitor?,
        isInsideIsolatedSubtree: Bool,
        ownsWorkerPermit: Bool,
        onProgress: @escaping ProgressHandler
    ) async throws -> FileNode? {
        try Task.checkCancellation()
        guard activityMonitor?.isActive != false else { throw CancellationError() }
        guard session.scope.allows(url, identity: nil) else { return nil }

        if !isInsideIsolatedSubtree,
           session.configuration.shouldIsolateSubtree(url) {
            return try await inspectIsolatedSubtree(
                url,
                session: session,
                ownsWorkerPermit: ownsWorkerPermit,
                onProgress: onProgress
            )
        }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: resourceKeys)
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

        let name = values.name ?? displayName(for: url)
        let isDirectory = values.isDirectory == true && values.isSymbolicLink != true

        guard isDirectory else {
            guard session.recordItem(
                at: url,
                activityMonitor: activityMonitor,
                onProgress: onProgress
            ) else { throw CancellationError() }
            let size = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            return FileNode(
                url: url,
                name: name,
                size: Int64(size),
                isDirectory: false,
                isReadable: true,
                children: []
            )
        }

        let identity = fileIdentity(for: url)
        try Task.checkCancellation()
        guard activityMonitor?.isActive != false else { throw CancellationError() }
        guard session.scope.allows(url, identity: identity) else { return nil }
        if let identity {
            guard session.visitedDirectories.insertIfNew(identity) else { return nil }
        }
        guard session.recordItem(
            at: url,
            activityMonitor: activityMonitor,
            onProgress: onProgress
        ) else { throw CancellationError() }

        let urls: [URL]
        do {
            urls = try session.configuration.directoryReader(url, Array(resourceKeys))
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

            for childURL in urls {
                try Task.checkCancellation()
                guard activityMonitor?.isActive != false else { throw CancellationError() }

                var acquiredPermit = session.parallelism.tryAcquire()
                while !acquiredPermit, !ownsWorkerPermit, pendingTaskCount > 0 {
                    if let completedChild = try await group.next() {
                        pendingTaskCount -= 1
                        if let completedChild {
                            measuredDirectItems += 1
                            total = addingWithoutOverflow(total, completedChild.size)
                            totalItems = addingWithoutOverflow(totalItems, completedChild.itemCount)
                            retainedChildren.insert(completedChild)
                        }
                    }
                    acquiredPermit = session.parallelism.tryAcquire()
                }

                if acquiredPermit {
                    pendingTaskCount += 1
                    group.addTask {
                        defer { session.parallelism.release() }
                        return try await inspect(
                            childURL,
                            session: session,
                            activityMonitor: activityMonitor,
                            isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                            ownsWorkerPermit: true,
                            onProgress: onProgress
                        )
                    }
                } else if let child = try await inspect(
                    childURL,
                    session: session,
                    activityMonitor: activityMonitor,
                    isInsideIsolatedSubtree: isInsideIsolatedSubtree,
                    ownsWorkerPermit: ownsWorkerPermit,
                    onProgress: onProgress
                ) {
                    measuredDirectItems += 1
                    total = addingWithoutOverflow(total, child.size)
                    totalItems = addingWithoutOverflow(totalItems, child.itemCount)
                    retainedChildren.insert(child)
                }
            }

            for try await child in group {
                pendingTaskCount -= 1
                guard let child else { continue }
                measuredDirectItems += 1
                total = addingWithoutOverflow(total, child.size)
                totalItems = addingWithoutOverflow(totalItems, child.itemCount)
                retainedChildren.insert(child)
            }
        }

        var children = retainedChildren.retainedNodes
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
            BoundedNodeAccumulator.isPreferred($0, over: $1)
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

    private static func fileIdentity(for url: URL) -> FileIdentity? {
        var metadata = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &metadata)
        }
        guard result == 0 else { return nil }
        return FileIdentity(
            device: UInt64(bitPattern: Int64(metadata.st_dev)),
            inode: UInt64(metadata.st_ino)
        )
    }

    private static func inspectIsolatedSubtree(
        _ url: URL,
        session: ScanSession,
        ownsWorkerPermit: Bool,
        onProgress: @escaping ProgressHandler
    ) async throws -> FileNode? {
        let monitor = ScanActivityMonitor()

        let resultBox = LockedResultBox<FileNode?>()
        let isolatedWorker = Task.detached(priority: .userInitiated) {
            do {
                let node = try await inspect(
                    url,
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
        let path = url.standardizedFileURL.path
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
    }

    var progressSnapshot: ScanProgress {
        progressLock.lock()
        defer { progressLock.unlock() }
        return progress
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
        progress.currentPath = url.path

        let now = DispatchTime.now().uptimeNanoseconds
        let emittedProgress: ScanProgress?
        if progress.itemsScanned == 1 || now &- lastProgressEmission >= 100_000_000 {
            lastProgressEmission = now
            emittedProgress = progress
        } else {
            emittedProgress = nil
        }
        progressLock.unlock()

        if let emittedProgress {
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
        progress.currentPath = url.path
        let emittedProgress = forceProgressEmission ? progress : nil
        progressLock.unlock()

        if let emittedProgress {
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
    let stalledSubtreeTimeout: TimeInterval
    let shouldIsolateSubtree: DiskScanner.SubtreeIsolationPredicate
    let directoryReader: DiskScanner.DirectoryReader
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

private struct BoundedNodeAccumulator {
    let capacity: Int
    private var heap: [FileNode] = []
    private(set) var discardedSize: Int64 = 0
    private(set) var discardedItemCount = 0
    private(set) var discardedDirectItems = 0

    init(capacity: Int) {
        self.capacity = capacity
    }

    var retainedNodes: [FileNode] { heap }

    mutating func insert(_ node: FileNode) {
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
              Self.isPreferred(node, over: leastPreferred) else {
            discard(node)
            return
        }

        heap[0] = node
        discard(leastPreferred)
        siftDown(from: 0)
    }

    static func isPreferred(_ left: FileNode, over right: FileNode) -> Bool {
        if left.size != right.size { return left.size > right.size }
        if left.isDirectory != right.isDirectory { return left.isDirectory }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }

    private mutating func discard(_ node: FileNode) {
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
            guard Self.isPreferred(heap[parent], over: heap[child]) else { break }
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

            if right < heap.count, Self.isPreferred(heap[left], over: heap[right]) {
                leastPreferred = right
            }

            guard Self.isPreferred(heap[parent], over: heap[leastPreferred]) else { return }
            heap.swapAt(parent, leastPreferred)
            parent = leastPreferred
        }
    }
}
