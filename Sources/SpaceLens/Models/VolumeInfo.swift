import Foundation

struct VolumeInfo: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isExternal: Bool
    let isReadOnly: Bool

    var id: String { url.standardizedFileURL.path }
    var usedCapacity: Int64 { max(totalCapacity - availableCapacity, 0) }
    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(max(Double(usedCapacity) / Double(totalCapacity), 0), 1)
    }
}
