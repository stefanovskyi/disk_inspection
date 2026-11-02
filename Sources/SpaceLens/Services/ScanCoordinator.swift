import Foundation

/// Admits scans and analyses first in, first out. Independent work never cancels
/// other work; anything beyond the concurrency limit waits for a free slot.
@MainActor
final class ScanCoordinator {
    enum Activity: Equatable, Sendable {
        case storage
        case aiCodingTools
        case aiModelsAndRuntimes
        case developerStorage
        case scanEverything
    }

    private struct Registration {
        let activity: Activity
        let id: UUID
        let start: @MainActor () -> Void
    }

    /// Every activity bounds its own traversal, so this limit also bounds total filesystem load.
    nonisolated static let defaultMaximumConcurrentActivities = 2

    private let maximumConcurrentActivities: Int
    private var running: [Registration] = []
    private var queued: [Registration] = []

    init(maximumConcurrentActivities: Int = ScanCoordinator.defaultMaximumConcurrentActivities) {
        precondition(maximumConcurrentActivities > 0)
        self.maximumConcurrentActivities = maximumConcurrentActivities
    }

    var runningActivities: [Activity] { running.map(\.activity) }
    var queuedActivities: [Activity] { queued.map(\.activity) }

    /// Calls `start` immediately when a slot is free, otherwise once one opens.
    /// The owner must call `finish` when the work completes or is cancelled.
    func enqueue(
        _ activity: Activity,
        id: UUID,
        start: @escaping @MainActor () -> Void
    ) {
        queued.append(Registration(activity: activity, id: id, start: start))
        startQueuedActivities()
    }

    /// Releases a running or still-queued activity. Late calls for finished work are ignored.
    func finish(_ activity: Activity, id: UUID) {
        func matches(_ registration: Registration) -> Bool {
            registration.activity == activity && registration.id == id
        }
        queued.removeAll(where: matches)
        running.removeAll(where: matches)
        startQueuedActivities()
    }

    private func startQueuedActivities() {
        while running.count < maximumConcurrentActivities, !queued.isEmpty {
            let next = queued.removeFirst()
            running.append(next)
            next.start()
        }
    }
}
