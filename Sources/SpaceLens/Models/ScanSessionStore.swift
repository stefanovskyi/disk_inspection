import Foundation

struct ScanSessionStore: Sendable {
    private var resultsByPath: [String: ScanResult] = [:]

    func result(for locationURL: URL) -> ScanResult? {
        resultsByPath[key(for: locationURL)]
    }

    mutating func store(_ result: ScanResult, for locationURL: URL) {
        resultsByPath[key(for: locationURL)] = result
    }

    mutating func removeResult(for locationURL: URL) {
        resultsByPath.removeValue(forKey: key(for: locationURL))
    }

    private func key(for locationURL: URL) -> String {
        locationURL.standardizedFileURL.path
    }
}

struct SessionFolder: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String

    init(url: URL) {
        let standardizedURL = url.standardizedFileURL
        self.url = standardizedURL
        self.name = standardizedURL.lastPathComponent.isEmpty
            ? standardizedURL.path
            : standardizedURL.lastPathComponent
    }

    var id: String { url.path }
}

struct PendingScanChoice: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case disk
        case folder

        var rescanButtonTitle: String {
            switch self {
            case .disk: "Rescan Disk"
            case .folder: "Rescan Folder"
            }
        }
    }

    let url: URL
    let name: String
    let kind: Kind

    init(volume: VolumeInfo) {
        self.url = volume.url.standardizedFileURL
        self.name = volume.name
        self.kind = .disk
    }

    init(folder: SessionFolder) {
        self.url = folder.url
        self.name = folder.name
        self.kind = .folder
    }
}
