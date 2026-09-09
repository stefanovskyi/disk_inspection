import Foundation
import XCTest
@testable import SpaceLens

final class FileNodeTests: XCTestCase {
    func testEqualityUsesImmutableArenaIdentity() throws {
        let rootURL = URL(fileURLWithPath: "/identity-test", isDirectory: true)
        let root = FileNode(
            url: rootURL,
            name: "identity-test",
            size: 1,
            isDirectory: true,
            isReadable: true,
            children: [
                FileNode(
                    url: rootURL.appendingPathComponent("child"),
                    name: "child",
                    size: 1,
                    isDirectory: false,
                    isReadable: true,
                    children: []
                )
            ]
        )

        XCTAssertEqual(root, root)
        XCTAssertNotEqual(root, try XCTUnwrap(root.children.first))

        let independentlyCreatedRoot = FileNode(
            url: rootURL,
            name: root.name,
            size: root.size,
            isDirectory: root.isDirectory,
            isReadable: root.isReadable,
            children: root.children
        )
        XCTAssertNotEqual(root, independentlyCreatedRoot)
    }
}
