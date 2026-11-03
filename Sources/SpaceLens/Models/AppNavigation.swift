enum AppSection: Sendable {
    case storage
    case aiCodingTools
    case aiModelsAndRuntimes
    case developerStorage
}

/// Records user navigation only; background result updates do not add entries.
struct NavigationHistory<Location: Equatable> {
    private var locations: [Location] = []

    var canGoBack: Bool { !locations.isEmpty }

    mutating func record(from previous: Location, to current: Location) {
        guard previous != current, locations.last != previous else { return }
        locations.append(previous)
    }

    mutating func goBack() -> Location? {
        locations.popLast()
    }

    mutating func removeAll(where shouldRemove: (Location) -> Bool) {
        locations.removeAll(where: shouldRemove)
    }
}
