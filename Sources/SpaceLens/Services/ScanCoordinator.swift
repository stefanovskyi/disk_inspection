import Foundation

@MainActor
final class ScanCoordinator {
    enum Activity: Equatable, Sendable {
        case storage
        case aiCodingTools
    }

    private struct Registration {
        let activity: Activity
        let id: UUID
        let cancel: @MainActor () -> Void
    }

    private var activeRegistration: Registration?

    var activeActivity: Activity? { activeRegistration?.activity }

    func begin(
        _ activity: Activity,
        id: UUID,
        cancel: @escaping @MainActor () -> Void
    ) {
        let previous = activeRegistration
        activeRegistration = Registration(activity: activity, id: id, cancel: cancel)
        if previous?.id != id {
            previous?.cancel()
        }
    }

    func finish(_ activity: Activity, id: UUID) {
        guard activeRegistration?.activity == activity,
              activeRegistration?.id == id else { return }
        activeRegistration = nil
    }

    func cancelActive() {
        let active = activeRegistration
        activeRegistration = nil
        active?.cancel()
    }
}
