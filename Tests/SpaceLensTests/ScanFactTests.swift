import Foundation
import XCTest
@testable import SpaceLens

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

final class ScanFactCatalogTests: XCTestCase {
    func testEveryTopicHasFiftyUniqueSourcedFactsOfReadableLength() {
        var seen: Set<String> = []
        for topic in ScanFactTopic.allCases {
            let facts = ScanFactCatalog.facts(for: topic)
            XCTAssertEqual(facts.count, ScanFactTopic.factsPerTopic, topic.title)
            for fact in facts {
                XCTAssertTrue(seen.insert(fact.text).inserted, "Duplicate: \(fact.text)")
                XCTAssertLessThanOrEqual(fact.text.count, ScanFact.maximumLength, fact.text)
                XCTAssertFalse(fact.source.isEmpty, fact.text)
            }
        }
    }

    func testReadingTimeGrowsWithLengthWithinBounds() {
        let short = ScanFact("Short.", source: "Test")
        let long = ScanFact(String(repeating: "word ", count: 48), source: "Test")
        XCTAssertEqual(short.readingDuration, 8)
        XCTAssertGreaterThan(long.readingDuration, short.readingDuration)
        XCTAssertLessThanOrEqual(long.readingDuration, 16)
    }
}

final class ScanFactDeckTests: XCTestCase {
    func testDealsEveryFactOnceBeforeAnyRepeat() {
        var generator = SeededGenerator(state: 7)
        var deck = ScanFactDeck(factCount: 50)

        for _ in 0..<3 {
            let round = (0..<50).map { _ in deck.deal(using: &generator) }
            XCTAssertEqual(Set(round).count, 50)
        }
    }

    func testNewRoundNeverRepeatsTheFactThatClosedTheLastOne() {
        for seed in 0..<200 {
            var generator = SeededGenerator(state: UInt64(seed))
            var deck = ScanFactDeck(factCount: 4)
            var previous: Int?
            for _ in 0..<40 {
                let index = deck.deal(using: &generator)
                XCTAssertNotEqual(index, previous)
                previous = index
            }
        }
    }

    func testIgnoresStoredIndexesOutsideTheCatalog() {
        var generator = SeededGenerator(state: 1)
        var deck = ScanFactDeck(factCount: 2, remaining: [99, 1])
        XCTAssertEqual(deck.deal(using: &generator), 1)
    }

    func testOrderIsRandomBetweenRounds() {
        var generator = SeededGenerator(state: 3)
        var deck = ScanFactDeck(factCount: 50)
        let first = (0..<50).map { _ in deck.deal(using: &generator) }
        let second = (0..<50).map { _ in deck.deal(using: &generator) }
        XCTAssertNotEqual(first, second)
    }
}

@MainActor
final class ScanFactRotationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "SpaceLensFactTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testContinuesTheSameRoundAfterRelaunch() {
        var generator = SeededGenerator(state: 11)
        var shown: Set<String> = []

        for _ in 0..<5 {
            // A new rotation per scan stands in for quitting and reopening the app.
            let rotation = ScanFactRotation(defaults: defaults)
            for _ in 0..<10 {
                let fact = rotation.next(for: .aiModels, using: &generator)
                XCTAssertTrue(shown.insert(fact.text).inserted, "Repeated: \(fact.text)")
            }
        }
        XCTAssertEqual(shown.count, ScanFactTopic.factsPerTopic)
    }

    func testTopicsRotateIndependentlyAndStayOnSubject() {
        var generator = SeededGenerator(state: 5)
        let rotation = ScanFactRotation(defaults: defaults)
        let codingFacts = ScanFactCatalog.facts(for: .codingTools).map(\.text)
        let diskFacts = ScanFactCatalog.facts(for: .diskStorage).map(\.text)

        for _ in 0..<60 {
            XCTAssertTrue(codingFacts.contains(rotation.next(for: .codingTools, using: &generator).text))
            XCTAssertTrue(diskFacts.contains(rotation.next(for: .diskStorage, using: &generator).text))
        }
    }
}
