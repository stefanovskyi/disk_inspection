import DiskArbitration
import Foundation

struct VolumeDiscovery: Sendable {
    private let keys: Set<URLResourceKey> = [
        .volumeNameKey,
        .volumeLocalizedNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeIsReadOnlyKey,
        .volumeUUIDStringKey,
        .volumeTypeNameKey,
        .volumeIsEncryptedKey,
        .volumeIsLocalKey
    ]

    func startupVolume() -> VolumeInfo? {
        volumeInfo(for: URL(fileURLWithPath: "/", isDirectory: true))
    }

    func mountedVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap(volumeInfo)
            .sorted {
                if $0.isStartupVolume != $1.isStartupVolume { return $0.isStartupVolume }
                if $0.isExternal != $1.isExternal { return !$0.isExternal }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private func volumeInfo(for url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let name = values.volumeLocalizedName
            ?? values.volumeName
            ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
        let isExternal = values.volumeIsRemovable == true
            || values.volumeIsEjectable == true
            || (url.path.hasPrefix("/Volumes/") && url.path != "/System/Volumes/Data")

        return VolumeInfo(
            url: url,
            name: name,
            totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(values.volumeAvailableCapacity ?? 0),
            isExternal: isExternal,
            isReadOnly: values.volumeIsReadOnly ?? false,
            uuid: values.volumeUUIDString,
            fileSystemType: values.volumeTypeName,
            isEncrypted: values.volumeIsEncrypted,
            isLocal: values.volumeIsLocal ?? true,
            physicalDeviceIdentifier: physicalDeviceIdentifier(for: url)
        )
    }

    /// Returns the whole-media identity used only to keep sibling filesystems
    /// from scanning concurrently. Failure deliberately falls back to the
    /// conservative grouping in `VolumeInfo`.
    private func physicalDeviceIdentifier(for url: URL) -> String? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(
                  kCFAllocatorDefault,
                  session,
                  url.standardizedFileURL as CFURL
              ) else { return nil }

        let wholeDisk = DADiskCopyWholeDisk(disk) ?? disk
        if let description = DADiskCopyDescription(wholeDisk) as NSDictionary?,
           let mediaUUID = description[kDADiskDescriptionMediaUUIDKey] as? UUID {
            return "uuid:\(mediaUUID.uuidString.lowercased())"
        }
        guard let name = DADiskGetBSDName(wholeDisk) else { return nil }
        return "bsd:\(String(cString: name))"
    }
}
