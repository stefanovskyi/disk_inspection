import Foundation
import os

enum SpaceLensSignposts {
    static let scan = OSSignposter(
        subsystem: "local.spacelens.app",
        category: "Scan"
    )
    static let directoryRead = OSSignposter(
        subsystem: "local.spacelens.app",
        category: "DirectoryRead"
    )
    static let chartLayout = OSSignposter(
        subsystem: "local.spacelens.app",
        category: "ChartLayout"
    )
    static let providerSubtree = OSSignposter(
        subsystem: "local.spacelens.app",
        category: "ProviderSubtree"
    )
    static let benchmark = OSSignposter(
        subsystem: "local.spacelens.app",
        category: "Benchmark"
    )
}
