import Foundation

struct FileNode: Identifiable, Equatable, Sendable {
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
        isReadable: Bool,
        children: [FileNode],
        itemCount: Int = 1,
        directItemCount: Int = 0,
        isAggregate: Bool = false
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.isReadable = isReadable
        self.children = children
        self.itemCount = itemCount
        self.directItemCount = directItemCount
        self.isAggregate = isAggregate
    }

    var id: String {
        let path = url.standardizedFileURL.path
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

    var descendantCount: Int {
        max(itemCount - 1, 0)
    }

    func percentage(of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(size) / Double(total), 0), 1)
    }
}

struct ScanProgress: Equatable, Sendable {
    var currentPath = ""
    var itemsScanned = 0
    var unreadableItems = 0
    var unresponsiveItems = 0
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
    var retainedNodes = 0
    var discardedNodes = 0
    var progressMerges = 0
    var progressEmissions = 0
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
