import Foundation
import XCTest
@testable import SpaceLens

final class SunburstLayoutTests: XCTestCase {
    func testSegmentsPreserveHierarchyAndProportion() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let deepLeaf = node("deep", size: 25, at: rootURL.appendingPathComponent("large/deep"))
        let large = node(
            "large",
            size: 75,
            at: rootURL.appendingPathComponent("large"),
            children: [deepLeaf]
        )
        let small = node("small", size: 25, at: rootURL.appendingPathComponent("small"))
        let root = node("test", size: 100, at: rootURL, children: [large, small])

        let segments = SunburstLayout.segments(for: root, maxDepth: 4, minimumAngularSpan: 0)
        let largeSegment = try XCTUnwrap(segments.first(where: { $0.node?.name == "large" }))
        let smallSegment = try XCTUnwrap(segments.first(where: { $0.node?.name == "small" }))
        let deepSegment = try XCTUnwrap(segments.first(where: { $0.node?.name == "deep" }))

        XCTAssertEqual(largeSegment.depth, 0)
        XCTAssertEqual(smallSegment.depth, 0)
        XCTAssertEqual(deepSegment.depth, 1)
        XCTAssertEqual(largeSegment.angularSpan / smallSegment.angularSpan, 3, accuracy: 0.001)
    }

    func testMaximumDepthIsRespected() {
        let rootURL = URL(fileURLWithPath: "/test")
        let levelThree = node("three", size: 1, at: rootURL.appendingPathComponent("one/two/three"))
        let levelTwo = node("two", size: 1, at: rootURL.appendingPathComponent("one/two"), children: [levelThree])
        let levelOne = node("one", size: 1, at: rootURL.appendingPathComponent("one"), children: [levelTwo])
        let root = node("test", size: 1, at: rootURL, children: [levelOne])

        let segments = SunburstLayout.segments(for: root, maxDepth: 2, minimumAngularSpan: 0)

        XCTAssertEqual(Set(segments.compactMap { $0.node?.name }), Set(["one", "two"]))
        XCTAssertEqual(segments.map(\.depth).max(), 1)
    }

    func testRequestedAngularExtentLeavesFreeSpaceOpen() {
        let rootURL = URL(fileURLWithPath: "/test")
        let first = node("first", size: 60, at: rootURL.appendingPathComponent("first"))
        let second = node("second", size: 40, at: rootURL.appendingPathComponent("second"))
        let root = node("test", size: 100, at: rootURL, children: [first, second])

        let segments = SunburstLayout.segments(
            for: root,
            maxDepth: 2,
            minimumAngularSpan: 0,
            angularExtent: .pi * 1.5
        )

        XCTAssertEqual(segments.map(\.endAngle).max() ?? 0, .pi * 1.5, accuracy: 0.001)
    }

    func testTopLevelHueIsStableWhenSiblingOrderChanges() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let targetURL = rootURL.appendingPathComponent("target")
        let firstRoot = node(
            "test",
            size: 100,
            at: rootURL,
            children: [
                node("target", size: 75, at: targetURL),
                node("other", size: 25, at: rootURL.appendingPathComponent("other"))
            ]
        )
        let reorderedRoot = node(
            "test",
            size: 200,
            at: rootURL,
            children: [
                node("other", size: 125, at: rootURL.appendingPathComponent("other")),
                node("target", size: 75, at: targetURL)
            ]
        )

        let firstHue = try XCTUnwrap(
            SunburstLayout.segments(for: firstRoot, minimumAngularSpan: 0)
                .first(where: { $0.node?.id == targetURL.path })?.hue
        )
        let reorderedHue = try XCTUnwrap(
            SunburstLayout.segments(for: reorderedRoot, minimumAngularSpan: 0)
                .first(where: { $0.node?.id == targetURL.path })?.hue
        )

        XCTAssertEqual(firstHue, reorderedHue)
    }

    func testSceneReusesItsLayoutForRepeatedHitTests() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let largeURL = rootURL.appendingPathComponent("large")
        let smallURL = rootURL.appendingPathComponent("small")
        let large = node(
            "large",
            size: 75,
            at: largeURL,
            children: [
                node("large-a", size: 50, at: largeURL.appendingPathComponent("a")),
                node("large-b", size: 25, at: largeURL.appendingPathComponent("b"))
            ]
        )
        let small = node(
            "small",
            size: 25,
            at: smallURL,
            children: [
                node("small-a", size: 15, at: smallURL.appendingPathComponent("a")),
                node("small-b", size: 10, at: smallURL.appendingPathComponent("b"))
            ]
        )
        let root = node("test", size: 100, at: rootURL, children: [large, small])
        let scene = SunburstScene(root: root, maxDepth: 4, minimumAngularSpan: 0)

        XCTAssertEqual(scene.segments.count, 6)
        XCTAssertEqual(scene.ringCount, 2)
        let largeIndex = try XCTUnwrap(scene.segmentIndex(atDepth: 0, angle: .pi))
        XCTAssertEqual(scene.segments[largeIndex].node?.name, "large")
        for _ in 0..<1_000 {
            XCTAssertEqual(scene.segmentIndex(atDepth: 0, angle: .pi), largeIndex)
        }
        for segment in scene.segments {
            let midpoint = segment.startAngle + (segment.angularSpan / 2)
            let index = try XCTUnwrap(scene.segmentIndex(atDepth: segment.depth, angle: midpoint))
            XCTAssertEqual(scene.segments[index].id, segment.id)
        }
        XCTAssertNil(scene.segmentIndex(atDepth: 0, angle: (.pi * 2) + 0.01))
        XCTAssertNil(scene.segmentIndex(atDepth: 2, angle: 0))
    }

    func testInteractiveSceneGroupsSubPercentChildrenAndPreservesTheirTotals() throws {
        let rootURL = URL(fileURLWithPath: "/test")
        let large = node("large", size: 950, at: rootURL.appendingPathComponent("large"))
        let small = (0..<10).map { index in
            node("small-\(index)", size: 5, at: rootURL.appendingPathComponent("small-\(index)"))
        }
        let root = node("test", size: 1_000, at: rootURL, children: [large] + small)
        let scene = SunburstScene(
            root: root,
            maxDepth: 4,
            angularExtent: .pi * 2,
            interactionRadius: 200,
            policy: .interactive
        )

        XCTAssertEqual(scene.segments.count, 2)
        let groupSegment = try XCTUnwrap(scene.segments.first(where: { $0.smallerItems != nil }))
        let group = try XCTUnwrap(groupSegment.smallerItems)
        XCTAssertEqual(group.name, "Smaller items")
        XCTAssertEqual(group.size, 50)
        XCTAssertEqual(group.itemCount, 10)
        XCTAssertEqual(group.children.count, 10)
        XCTAssertEqual(scene.segments.reduce(Int64(0)) { $0 + $1.size }, root.size)

        let midpoint = groupSegment.startAngle + (groupSegment.angularSpan / 2)
        let hitIndex = try XCTUnwrap(
            scene.segmentIndex(atDepth: groupSegment.depth, angle: midpoint)
        )
        XCTAssertEqual(scene.segments[hitIndex].smallerItems?.id, group.id)
    }

    func testInteractivePolicyUsesPixelFloorAndSceneHonorsSegmentBudget() {
        XCTAssertEqual(
            SunburstScenePolicy.interactive.minimumAngularSpan(
                angularExtent: .pi,
                interactionRadius: 100
            ),
            0.06,
            accuracy: 0.000_001
        )

        let rootURL = URL(fileURLWithPath: "/test")
        let children = (0..<30).map { index in
            let directoryURL = rootURL.appendingPathComponent("directory-\(index)")
            let leaf = node("leaf", size: 100, at: directoryURL.appendingPathComponent("leaf"))
            return node("directory-\(index)", size: 100, at: directoryURL, children: [leaf])
        }
        let root = node("test", size: 3_000, at: rootURL, children: children)
        let scene = SunburstScene(
            root: root,
            maxDepth: 4,
            minimumAngularSpan: 0,
            angularExtent: .pi * 2,
            maximumSegmentCount: 20
        )

        XCTAssertEqual(scene.segments.count, 20)
        XCTAssertTrue(scene.segments.allSatisfy { $0.depth == 0 })
        for segment in scene.segments {
            let midpoint = segment.startAngle + (segment.angularSpan / 2)
            XCTAssertNotNil(scene.segmentIndex(atDepth: segment.depth, angle: midpoint))
        }
    }

    private func node(_ name: String, size: Int64, at url: URL, children: [FileNode] = []) -> FileNode {
        FileNode(
            url: url,
            name: name,
            size: size,
            isDirectory: !children.isEmpty,
            isReadable: true,
            children: children
        )
    }
}
