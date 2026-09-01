import Foundation

struct VolumeDiscovery {
    private let keys: Set<URLResourceKey> = [
        .volumeNameKey,
        .volumeLocalizedNameKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeIsReadOnlyKey
    ]

    func mountedVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap(volumeInfo)
            .sorted {
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
            isReadOnly: values.volumeIsReadOnly ?? false
        )
    }
}
