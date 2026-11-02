import Foundation

/// One scan or analysis as shown in the sidebar progress panel.
struct ScanActivity: Identifiable, Equatable, Sendable {
    enum Target: Hashable, Sendable {
        case storage(path: String)
        case analysis(ScanEverythingAnalysis)
        case batch(UUID)
    }

    static let waitingStatus = "Waiting to start"

    let target: Target
    let systemImage: String
    let title: String
    let status: String
    let detail: String
    var location: String?
    var currentPath: String?
    var fraction: Double?
    /// `nil` while the activity waits for a free slot in the queue.
    let startedAt: Date?

    var id: Target { target }
    var isQueued: Bool { startedAt == nil }

    /// Running work first; each group keeps its original order.
    static func ordered(_ activities: [ScanActivity]) -> [ScanActivity] {
        activities.filter { !$0.isQueued } + activities.filter(\.isQueued)
    }
}
