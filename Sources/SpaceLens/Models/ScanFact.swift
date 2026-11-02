import Foundation

enum ScanFactTopic: String, CaseIterable, Sendable {
    case codingTools
    case aiModels
    case developerStorage
    case diskStorage

    static let factsPerTopic = 50

    var title: String {
        switch self {
        case .codingTools: "AI Coding Tools"
        case .aiModels: "AI Models"
        case .developerStorage: "Developer Storage"
        case .diskStorage: "Disks & Storage"
        }
    }

    var systemImage: String {
        switch self {
        case .codingTools: "wand.and.stars"
        case .aiModels: "cpu"
        case .developerStorage: "hammer.fill"
        case .diskStorage: "internaldrive.fill"
        }
    }
}

/// A short fact shown while a scan runs. Figures that change carry their own date
/// so a fact stays true after the catalog was last reviewed.
struct ScanFact: Equatable, Sendable {
    static let maximumLength = 240

    let text: String
    let source: String

    init(_ text: String, source: String) {
        self.text = text
        self.source = source
    }

    /// Long enough to read the fact unhurried, whatever its length.
    var readingDuration: TimeInterval {
        min(max(7 + Double(text.count) * 0.04, 8), 16)
    }
}

/// Deals every fact once in random order before any fact repeats.
struct ScanFactDeck: Equatable, Sendable {
    let factCount: Int
    private(set) var remaining: [Int]
    private(set) var lastDealt: Int?

    init(factCount: Int, remaining: [Int] = [], lastDealt: Int? = nil) {
        self.factCount = factCount
        self.remaining = remaining.filter { (0..<factCount).contains($0) }
        self.lastDealt = lastDealt
    }

    mutating func deal<Generator: RandomNumberGenerator>(using generator: inout Generator) -> Int {
        precondition(factCount > 0)
        if remaining.isEmpty {
            remaining = Array(0..<factCount).shuffled(using: &generator)
            // A new round must not open with the fact that closed the last one.
            if factCount > 1, remaining.last == lastDealt {
                remaining.swapAt(0, remaining.count - 1)
            }
        }
        let index = remaining.removeLast()
        lastDealt = index
        return index
    }
}

/// Keeps each topic's deck across scans and launches, so a short scan
/// continues where the previous one stopped instead of reshuffling.
@MainActor
final class ScanFactRotation {
    private let defaults: UserDefaults
    private var decks: [ScanFactTopic: ScanFactDeck] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func next(for topic: ScanFactTopic) -> ScanFact {
        var generator = SystemRandomNumberGenerator()
        return next(for: topic, using: &generator)
    }

    func next<Generator: RandomNumberGenerator>(
        for topic: ScanFactTopic,
        using generator: inout Generator
    ) -> ScanFact {
        let facts = ScanFactCatalog.facts(for: topic)
        var deck = decks[topic] ?? storedDeck(for: topic, factCount: facts.count)
        let index = deck.deal(using: &generator)
        decks[topic] = deck
        defaults.set(deck.remaining, forKey: remainingKey(topic))
        defaults.set(index, forKey: lastDealtKey(topic))
        return facts[index]
    }

    private func storedDeck(for topic: ScanFactTopic, factCount: Int) -> ScanFactDeck {
        ScanFactDeck(
            factCount: factCount,
            remaining: defaults.array(forKey: remainingKey(topic)) as? [Int] ?? [],
            lastDealt: defaults.object(forKey: lastDealtKey(topic)) as? Int
        )
    }

    private func remainingKey(_ topic: ScanFactTopic) -> String {
        "scanFacts.\(topic.rawValue).remaining"
    }

    private func lastDealtKey(_ topic: ScanFactTopic) -> String {
        "scanFacts.\(topic.rawValue).lastDealt"
    }
}
