import Foundation

enum FullDiskAccessStatus: Equatable, Sendable {
    case notRequired
    case granted
    case needsUserApproval
}

struct FullDiskAccessChecker: Sendable {
    typealias AccessProbe = @Sendable () -> Bool

    private let accessProbe: AccessProbe

    init(accessProbe: AccessProbe? = nil) {
        self.accessProbe = accessProbe ?? {
            Self.canReadProtectedSystemDatabase()
        }
    }

    func status(for scanURL: URL) -> FullDiskAccessStatus {
        guard scanURL.standardizedFileURL.path == "/" else {
            return .notRequired
        }
        return accessProbe() ? .granted : .needsUserApproval
    }

    private static func canReadProtectedSystemDatabase() -> Bool {
        let path = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }
}
