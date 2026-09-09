import Foundation

struct PreviousScanSummary: Codable, Equatable, Sendable {
    // Persist every child retained by DiskScanner through every level the chart can render.
    // This keeps a reopened scan visually consistent with the result shown at completion.
    private static let retainedChildLimit = DiskScanner.retainedChildLimit
    private static let retainedDepth = 6

    let volumeIdentifier: String
    let scannedAt: Date
    let duration: TimeInterval
    let itemsScanned: Int
    let unreadableItems: Int
    let root: PreviousScanNode

    init(result: ScanResult, volume: VolumeInfo, scannedAt: Date = Date()) {
        volumeIdentifier = volume.persistentIdentifier
        self.scannedAt = scannedAt
        duration = result.duration
        itemsScanned = result.itemsScanned
        unreadableItems = result.unreadableItems
        root = PreviousScanNode(
            capturing: result.root,
            remainingDepth: Self.retainedDepth,
            childLimit: Self.retainedChildLimit
        )
    }

    func makeRoot(at volumeURL: URL) -> FileNode {
        FileNode(rootURL: volumeURL, snapshot: root.fileNodeSnapshot)
    }

    func makeResult(at volumeURL: URL) -> ScanResult {
        ScanResult(
            root: makeRoot(at: volumeURL),
            duration: duration,
            itemsScanned: itemsScanned,
            unreadableItems: unreadableItems
        )
    }
}

struct PreviousScanNode: Codable, Equatable, Sendable {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let isReadable: Bool
    let children: [PreviousScanNode]
    let itemCount: Int
    let directItemCount: Int
    let isAggregate: Bool

    init(
        capturing node: FileNode,
        remainingDepth: Int,
        childLimit: Int
    ) {
        name = node.name
        size = node.size
        isDirectory = node.isDirectory
        isReadable = node.isReadable
        itemCount = node.itemCount
        directItemCount = node.directItemCount
        isAggregate = node.isAggregate

        guard remainingDepth > 0, childLimit > 0 else {
            children = []
            return
        }

        let ordinaryChildren = node.sortedChildren.filter { !$0.isAggregate }
        let retainedChildren = Array(ordinaryChildren.prefix(childLimit))
        var capturedChildren = retainedChildren.map {
            PreviousScanNode(
                capturing: $0,
                remainingDepth: remainingDepth - 1,
                childLimit: childLimit
            )
        }
        let retainedIDs = Set(retainedChildren.map(\.id))
        let omittedChildren = node.children.filter {
            $0.isAggregate || !retainedIDs.contains($0.id)
        }
        let omittedSize = omittedChildren.reduce(Int64(0)) {
            Self.addingWithoutOverflow($0, $1.size)
        }
        let omittedItems = omittedChildren.reduce(0) {
            Self.addingWithoutOverflow($0, $1.itemCount)
        }
        if omittedSize > 0 || omittedItems > 0 {
            capturedChildren.append(
                PreviousScanNode(
                    name: "Smaller items",
                    size: omittedSize,
                    itemCount: max(omittedItems, 1)
                )
            )
        }
        children = capturedChildren
    }

    private init(name: String, size: Int64, itemCount: Int) {
        self.name = name
        self.size = size
        isDirectory = false
        isReadable = true
        children = []
        self.itemCount = itemCount
        directItemCount = 0
        isAggregate = true
    }

    var fileNodeSnapshot: FileNodeSnapshot {
        FileNodeSnapshot(
            name: name,
            size: size,
            isDirectory: isDirectory,
            isReadable: isReadable,
            children: children.map(\.fileNodeSnapshot),
            itemCount: itemCount,
            directItemCount: directItemCount,
            isAggregate: isAggregate
        )
    }

    private static func addingWithoutOverflow(_ left: Int64, _ right: Int64) -> Int64 {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? Int64.max : result.partialValue
    }

    private static func addingWithoutOverflow(_ left: Int, _ right: Int) -> Int {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? Int.max : result.partialValue
    }
}
