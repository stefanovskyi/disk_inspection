import XCTest
@testable import SpaceLens

final class BrandLogoTests: XCTestCase {
    func testEverySupportedToolAndRuntimeHasALogo() {
        XCTAssertTrue(AICodingToolsCatalog.supportedTools.allSatisfy { $0.logo != nil })
        let branded = AIModelsCatalog.supportedRuntimes.filter { $0.logo != nil }.map(\.id)
        XCTAssertEqual(branded, [.ollama, .lmStudio, .llamaCpp, .huggingFace])
    }

    func testEcosystemsUseTheirLanguageLogos() {
        XCTAssertEqual(DeveloperEcosystemID.nodeAndWeb.logo, .nodeJS)
        XCTAssertEqual(DeveloperEcosystemID.python.logo, .python)
        XCTAssertEqual(DeveloperEcosystemID.javaAndJVM.logo, .java)
    }

    func testSpecificToolWinsOverItsLanguage() {
        XCTAssertEqual(BrandLogoCatalog.logo(forStorageLocationNamed: "Gradle JDKs"), .gradle)
        XCTAssertEqual(BrandLogoCatalog.logo(forStorageLocationNamed: "uv Python versions"), .uv)
        XCTAssertEqual(BrandLogoCatalog.logo(forStorageLocationNamed: "Fluvial data"), nil)
    }

    func testModelPublisherMatching() {
        XCTAssertEqual(BrandLogoCatalog.logo(forModelNamed: "mlx-community/Llama-3.3"), .meta)
        XCTAssertEqual(BrandLogoCatalog.logo(forModelNamed: "phi4:latest"), .microsoft)
        XCTAssertNil(BrandLogoCatalog.logo(forModelNamed: "sapphire-7b"))
    }

    func testStorageItemsPreferRealSystemIcons() {
        let app = URL(fileURLWithPath: "/Applications/Cursor.app")
        XCTAssertEqual(
            StorageItemIcon.resolve(url: app, isDirectory: true),
            .system(.file(app), fallback: .cursor)
        )
        XCTAssertEqual(
            StorageItemIcon.resolve(
                url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Cursor"),
                isDirectory: true
            ),
            .system(.applicationNamed("Cursor"), fallback: .cursor)
        )
        XCTAssertEqual(
            StorageItemIcon.resolve(url: URL(fileURLWithPath: "/work/Cursor"), isDirectory: true),
            .generic
        )
    }

    func testProductNamesOnlyMatchWhereToolDataIsExpected() {
        XCTAssertEqual(
            StorageItemIcon.resolve(url: URL(fileURLWithPath: "/work/node_modules/react"), isDirectory: true),
            .brand(.react)
        )
        XCTAssertEqual(
            StorageItemIcon.resolve(url: URL(fileURLWithPath: "/work/react"), isDirectory: true),
            .generic
        )
    }

    func testHelpersResolveToTheirApplication() {
        XCTAssertEqual(
            SystemIconSource.bundleIdentifierCandidates(for: "com.tinyspeck.slackmacgap.ShipIt"),
            ["com.tinyspeck.slackmacgap.ShipIt", "com.tinyspeck.slackmacgap", "com.tinyspeck"]
        )
    }
}
