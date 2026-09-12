import Foundation

struct ScanDeviceKey: Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

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
    let scanDeviceKey: ScanDeviceKey

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
        isLocal: Bool = true,
        physicalDeviceIdentifier: String? = nil
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
        let resolvedIdentifier = physicalDeviceIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedIdentifier, !resolvedIdentifier.isEmpty {
            scanDeviceKey = ScanDeviceKey(rawValue: "physical:\(resolvedIdentifier)")
        } else if isExternal {
            // Disk Arbitration normally supplies a whole-media identifier. If it
            // cannot, keep unrelated external mounts eligible for concurrency.
            scanDeviceKey = ScanDeviceKey(rawValue: "external:\(url.standardizedFileURL.path)")
        } else {
            // Unknown internal mounts are grouped together conservatively. This
            // also keeps the startup System/Data volume family on one device.
            scanDeviceKey = ScanDeviceKey(rawValue: "internal:unknown")
        }
    }

    var id: String { url.standardizedFileURL.path }
    var persistentIdentifier: String {
        uuid.map { "uuid:\($0)" } ?? "path:\(url.standardizedFileURL.path)"
    }
    /// The mounted volume that provides the currently running macOS root.
    var isStartupVolume: Bool { url.standardizedFileURL.path == "/" }
    var usedCapacity: Int64 { max(totalCapacity - availableCapacity, 0) }
    var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return min(max(Double(usedCapacity) / Double(totalCapacity), 0), 1)
    }
}
