import Foundation

/// A lightweight view into the compact arena for one retained scan result.
/// The arena stores the root URL once and parent-relative names for descendants.
struct FileNode: Identifiable, Equatable, Sendable {
    private struct Record: Sendable {
        let parentIndex: Int
        let name: String
        let size: Int64
        let isDirectory: Bool
        let isReadable: Bool
        var firstChildIndex: Int
        var childCount: Int
        let itemCount: Int
        let directItemCount: Int
        let isAggregate: Bool
    }

    private final class Storage: @unchecked Sendable {
        let rootURL: URL
        let records: [Record]

        init(rootURL: URL, snapshot: FileNodeSnapshot) {
            self.rootURL = rootURL.standardizedFileURL
            var records: [Record] = []

            func record(for node: FileNodeSnapshot, parentIndex: Int) -> Record {
                Record(
                    parentIndex: parentIndex,
                    name: node.name,
                    size: node.size,
                    isDirectory: node.isDirectory,
                    isReadable: node.isReadable,
                    firstChildIndex: -1,
                    childCount: 0,
                    itemCount: node.itemCount,
                    directItemCount: node.directItemCount,
                    isAggregate: node.isAggregate
                )
            }

            func appendChildren(of node: FileNodeSnapshot, at index: Int) {
                guard !node.children.isEmpty else { return }
                let firstChildIndex = records.count
                for child in node.children {
                    records.append(record(for: child, parentIndex: index))
                }
                records[index].firstChildIndex = firstChildIndex
                records[index].childCount = node.children.count
                for (offset, child) in node.children.enumerated() {
                    appendChildren(of: child, at: firstChildIndex + offset)
                }
            }

            records.append(record(for: snapshot, parentIndex: -1))
            appendChildren(of: snapshot, at: 0)
            self.records = records
        }
    }

    private let storage: Storage
    private let index: Int

    init(
        url: URL,
        name: String,
        size: Int64,
        isDirectory: Bool,
        isReadable: Bool,
        children: [FileNode],
        itemCount: Int = 1,
        directItemCount: Int = 0,
        isAggregate: Bool = false
    ) {
        self.init(
            rootURL: url,
            snapshot: FileNodeSnapshot(
                name: name,
                size: size,
                isDirectory: isDirectory,
                isReadable: isReadable,
                children: children.map(\.snapshot),
                itemCount: itemCount,
                directItemCount: directItemCount,
                isAggregate: isAggregate
            )
        )
    }

    init(rootURL: URL, snapshot: FileNodeSnapshot) {
        storage = Storage(rootURL: rootURL, snapshot: snapshot)
        index = 0
    }

    private init(storage: Storage, index: Int) {
        self.storage = storage
        self.index = index
    }

    private var record: Record { storage.records[index] }

    var url: URL {
        guard index != 0 else { return storage.rootURL }

        var components: [String] = []
        var currentIndex = index
        while currentIndex > 0 {
            let current = storage.records[currentIndex]
            if !current.isAggregate {
                components.append(current.name)
            }
            currentIndex = current.parentIndex
        }

        return components.reversed().reduce(storage.rootURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }

    var name: String { storage.records[index].name }
    var size: Int64 { storage.records[index].size }
    var isDirectory: Bool { storage.records[index].isDirectory }
    var isReadable: Bool { storage.records[index].isReadable }
    var itemCount: Int { storage.records[index].itemCount }
    var directItemCount: Int { storage.records[index].directItemCount }
    var isAggregate: Bool { storage.records[index].isAggregate }

    var children: [FileNode] {
        guard record.childCount > 0 else { return [] }
        let childRange = record.firstChildIndex..<(record.firstChildIndex + record.childCount)
        return childRange.map { FileNode(storage: storage, index: $0) }
    }

    var id: String {
        let path = url.path
        return isAggregate ? "\(path)#spacelens-aggregate" : path
    }

    var sortedChildren: [FileNode] {
        children.sorted {
            if $0.size == $1.size {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.size > $1.size
        }
    }

    var descendantCount: Int { max(itemCount - 1, 0) }

    func percentage(of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(size) / Double(total), 0), 1)
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.storage === rhs.storage && lhs.index == rhs.index
    }

    /// Allocation-shape facts used by regression tests without exposing the arena.
    var storageMetrics: FileNodeStorageMetrics {
        FileNodeStorageMetrics(
            nodeCount: storage.records.count,
            storedAbsolutePathCount: 1,
            childIndexArrayCount: 0
        )
    }

    private var snapshot: FileNodeSnapshot {
        FileNodeSnapshot(
            name: name,
            size: size,
            isDirectory: isDirectory,
            isReadable: isReadable,
            children: children.map(\.snapshot),
            itemCount: itemCount,
            directItemCount: directItemCount,
            isAggregate: isAggregate
        )
    }
}

struct FileNodeStorageMetrics: Equatable, Sendable {
    let nodeCount: Int
    let storedAbsolutePathCount: Int
    let childIndexArrayCount: Int
}

/// Short-lived scan assembly value with no URL or absolute path storage.
struct FileNodeSnapshot: Equatable, Sendable {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let isReadable: Bool
    let children: [FileNodeSnapshot]
    let itemCount: Int
    let directItemCount: Int
    let isAggregate: Bool

    init(
        name: String,
        size: Int64,
        isDirectory: Bool,
        isReadable: Bool,
        children: [FileNodeSnapshot],
        itemCount: Int = 1,
        directItemCount: Int = 0,
        isAggregate: Bool = false
    ) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.isReadable = isReadable
        self.children = children
        self.itemCount = itemCount
        self.directItemCount = directItemCount
        self.isAggregate = isAggregate
    }
}

struct ScanProgress: Equatable, Sendable {
    var currentPath = ""
    var itemsScanned = 0
    var unreadableItems = 0
    var unresponsiveItems = 0
    var mappedBytes: Int64 = 0
    var previewRoot: FileNode?
}

struct ScanResult: Equatable, Sendable {
    let root: FileNode
    let duration: TimeInterval
    let itemsScanned: Int
    let unreadableItems: Int
    let diagnostics: ScanDiagnosticSnapshot

    init(
        root: FileNode,
        duration: TimeInterval,
        itemsScanned: Int,
        unreadableItems: Int,
        diagnostics: ScanDiagnosticSnapshot = .init()
    ) {
        self.root = root
        self.duration = duration
        self.itemsScanned = itemsScanned
        self.unreadableItems = unreadableItems
        self.diagnostics = diagnostics
    }
}

struct ScanDiagnosticSnapshot: Codable, Equatable, Sendable {
    var syscallBatches = 0
    var fallbackLstatCalls = 0
    var bufferAllocations = 0
    var directoryTasks = 0
    var directoryCount = 0
    var retainedNodes = 0
    var discardedNodes = 0
    var progressMerges = 0
    var progressEmissions = 0
    var providerTimeouts = 0
    var abandonedWorkers = 0
    var retainedArenaNodeCount = 0
    var arenaConstructionDurationSeconds: TimeInterval = 0
    var rssBeforeArenaConstructionBytes: UInt64 = 0
    var rssAfterArenaConstructionBytes: UInt64 = 0
}

enum ScanFailure: LocalizedError {
    case inaccessible(URL)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .inaccessible(let url):
            return "SpaceLens could not read \(url.path). Check its permissions and try again."
        case .cancelled:
            return "The scan was cancelled."
        }
    }
}
