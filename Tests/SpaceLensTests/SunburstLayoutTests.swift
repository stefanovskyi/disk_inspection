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
        let largeSegment = try XCTUnwrap(segments.first(where: { $0.node.name == "large" }))
        let smallSegment = try XCTUnwrap(segments.first(where: { $0.node.name == "small" }))
        let deepSegment = try XCTUnwrap(segments.first(where: { $0.node.name == "deep" }))

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

        XCTAssertEqual(Set(segments.map(\.node.name)), Set(["one", "two"]))
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
