import Foundation

struct VolumeInfo: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isExternal: Bool
    let isReadOnly: Bool
    let uuid: String?
    let fileSystemType: String?
    let isEncrypted: Bool?
    let isLocal: Bool

    init(
        url: URL,
        name: String,
        totalCapacity: Int64,
        availableCapacity: Int64,
        isExternal: Bool,
        isReadOnly: Bool,
        uuid: String? = nil,
        fileSystemType: String? = nil,
        isEncrypted: Bool? = nil,
        isLocal: Bool = true
    ) {
        self.url = url
        self.name = name
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.isExternal = isExternal
        self.isReadOnly = isReadOnly
        self.uuid = uuid
        self.fileSystemType = fileSystemType
        self.isEncrypted = isEncrypted
        self.isLocal = isLocal
    }

    var id: String { url.standardizedFileURL.path }
    var persistentIdentifier: String {
        uuid.map { "uuid:\($0)" } ?? "path:\(url.standardizedFileURL.path)"
    }
    var usedCapacity: Int64 { max(totalCapacity - availableCapacity, 0) }
    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(max(Double(usedCapacity) / Double(totalCapacity), 0), 1)
    }
}
