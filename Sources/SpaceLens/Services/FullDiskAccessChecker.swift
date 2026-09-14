import Foundation

enum FullDiskAccessStatus: Equatable, Sendable {
    case granted
    case needsUserApproval
}

struct FullDiskAccessChecker: Sendable {
    typealias AccessProbe = @Sendable () -> Bool

    private let accessProbe: AccessProbe

    init(accessProbe: AccessProbe? = nil) {
        self.accessProbe = accessProbe ?? {
            Self.canReadProtectedUserDatabase()
        }
    }

    /// Re-runs the protected-file probe immediately before a scan or analysis begins.
    func status() -> FullDiskAccessStatus {
        accessProbe() ? .granted : .needsUserApproval
    }

    static func protectedDatabaseURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/com.apple.TCC", isDirectory: true)
            .appendingPathComponent("TCC.db", isDirectory: false)
    }

    private static func canReadProtectedUserDatabase() -> Bool {
        let databaseURL = protectedDatabaseURL(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        guard let handle = FileHandle(forReadingAtPath: databaseURL.path) else { return false }
        try? handle.close()
        return true
    }
}
