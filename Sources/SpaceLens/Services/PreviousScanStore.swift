import Foundation

struct PreviousScanStore: Sendable {
    private struct Archive: Codable {
        let version: Int
        var summaries: [String: PreviousScanSummary]
    }

    private static let archiveVersion = 1
    private static let retainedSummaryLimit = 24
    private static let accessLock = NSLock()

    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() -> [String: PreviousScanSummary] {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        return loadWithoutLocking()
    }

    private func loadWithoutLocking() -> [String: PreviousScanSummary] {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == Self.archiveVersion else { return [:] }
        return archive.summaries
    }

    func store(_ summary: PreviousScanSummary) throws {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }

        var summaries = loadWithoutLocking()
        summaries[summary.volumeIdentifier] = summary
        if summaries.count > Self.retainedSummaryLimit {
            let retainedIDs = Set(
                summaries.values
                    .sorted { $0.scannedAt > $1.scannedAt }
                    .prefix(Self.retainedSummaryLimit)
                    .map(\.volumeIdentifier)
            )
            summaries = summaries.filter { retainedIDs.contains($0.key) }
        }

        let archive = Archive(version: Self.archiveVersion, summaries: summaries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("SpaceLens", isDirectory: true)
            .appendingPathComponent("PreviousScans.json", isDirectory: false)
    }
}
