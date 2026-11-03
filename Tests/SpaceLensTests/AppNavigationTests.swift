import AppKit
import XCTest
@testable import SpaceLens

@MainActor
final class AppNavigationTests: XCTestCase {
    private let folderURL = URL(fileURLWithPath: "/tmp/SpaceLensNavigationTests/folder")

    func testBackRetracesFoldersAndBreadcrumbJumps() async throws {
        let model = try await makeModel()
        let initialNodeID = model.currentNode?.id
        try await openFolder(in: model)
        let root = try XCTUnwrap(model.currentNode)
        let child = try XCTUnwrap(root.children.first)
        let grandchild = try XCTUnwrap(child.children.first)

        model.navigate(into: child)
        model.navigate(into: grandchild)
        model.navigate(toBreadcrumbAt: 0)
        model.navigateBack()
        XCTAssertEqual(model.navigationPath.map(\.id), [root.id, child.id, grandchild.id])
        model.navigateBack()
        XCTAssertEqual(model.currentNode?.id, child.id)
        model.navigateBack()
        XCTAssertEqual(model.navigationPath.map(\.id), [root.id])
        model.navigateBack()
        XCTAssertEqual(model.currentNode?.id, initialNodeID)
        XCTAssertFalse(model.canNavigateBack)
    }

    func testBackRestoresDeepChartJumpAcrossAllPages() async throws {
        let model = try await makeModel()
        try await openFolder(in: model)
        let root = try XCTUnwrap(model.currentNode)
        let grandchild = try XCTUnwrap(root.children.first?.children.first)
        model.navigate(into: grandchild)

        model.showAICodingTools()
        model.selectAICodingTool(.cursor)
        model.showAIModelsAndRuntimes()
        model.selectAIModelRuntime(.ollama)
        model.showDeveloperStorage()
        model.selectDeveloperEcosystem(.python)

        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .developerStorage)
        XCTAssertNil(model.developerStorage.selectedEcosystemID)
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .aiModelsAndRuntimes)
        XCTAssertEqual(model.aiModelsAndRuntimes.selectedRuntimeID, .ollama)
        model.navigateBack()
        XCTAssertNil(model.aiModelsAndRuntimes.selectedRuntimeID)
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .aiCodingTools)
        XCTAssertEqual(model.aiCodingTools.selectedToolID, .cursor)
        model.navigateBack()
        XCTAssertNil(model.aiCodingTools.selectedToolID)
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .storage)
        XCTAssertEqual(model.navigationPath.map(\.id), [root.id, grandchild.id])
        model.navigateBack()
        XCTAssertEqual(model.currentNode?.id, root.id)
    }

    func testRepeatedSelectionsAndInvalidDrillDownDoNotCreateHistory() async throws {
        let model = try await makeModel()
        let initialNodeID = model.currentNode?.id
        model.showAICodingTools()
        model.showAICodingTools()
        model.selectAICodingTool(.cursor)
        model.selectAICodingTool(.cursor)
        model.navigate(toBreadcrumbAt: 99)
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .aiCodingTools)
        XCTAssertNil(model.aiCodingTools.selectedToolID)
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .storage)
        XCTAssertFalse(model.canNavigateBack)
        model.navigateBack()
        XCTAssertFalse(model.canNavigateBack)

        try await openFolder(in: model)
        let root = try XCTUnwrap(model.currentNode)
        model.navigate(into: root)
        model.navigate(into: NavigationTestScanner.result(at: URL(fileURLWithPath: "/outside")).root)
        model.navigate(toBreadcrumbAt: 0)
        model.navigateBack()
        XCTAssertEqual(model.currentNode?.id, initialNodeID)
    }

    func testBackDuringScanLeavesItRunningAndRestoresFinishedResult() async throws {
        let scanner = NavigationTestScanner()
        let model = try await makeModel(scanner: scanner)
        await scanner.setBlocked(true)
        model.showAICodingTools()
        model.inspectAICodingNode(NavigationTestScanner.result(at: folderURL).root)
        XCTAssertTrue(model.isScanning)
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .aiCodingTools)
        XCTAssertTrue(model.isScanActive(at: folderURL))

        model.selectSessionFolder(SessionFolder(url: folderURL))
        model.showDeveloperStorage()
        await scanner.setBlocked(false)
        try await waitUntil { !model.isScanActive(at: self.folderURL) }
        XCTAssertEqual(model.selectedSection, .developerStorage)

        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .storage)
        XCTAssertEqual(model.currentNode?.id, folderURL.path)
        XCTAssertNotNil(model.result)
        let calls = await scanner.calls
        XCTAssertEqual(calls, 1, "Back must follow existing work without starting another scan")
    }

    func testBackReturnsToCachedFolderWithoutRescanning() async throws {
        let scanner = NavigationTestScanner()
        let model = try await makeModel(scanner: scanner)
        try await openFolder(in: model)
        let child = try XCTUnwrap(model.currentNode?.children.first)
        model.navigate(into: child)
        let otherURL = folderURL.deletingLastPathComponent().appendingPathComponent("other")
        model.inspectAICodingNode(NavigationTestScanner.result(at: otherURL).root)
        try await waitUntil { !model.isScanning }

        model.navigateBack()
        XCTAssertEqual(model.currentNode?.id, child.id)
        XCTAssertEqual(model.navigationPath.first?.id, folderURL.path)
        let calls = await scanner.calls
        XCTAssertEqual(calls, 2)
    }

    func testBackUsesLatestRescanAndStopsAtMissingDescendant() async throws {
        let scanner = NavigationTestScanner()
        let model = try await makeModel(scanner: scanner)
        try await openFolder(in: model)
        let child = try XCTUnwrap(model.currentNode?.children.first)
        model.navigate(into: child)
        await scanner.setIncludesFolders(false)
        model.rescan()
        model.showAICodingTools()
        try await waitUntil { !model.isScanActive(at: self.folderURL) }

        model.navigateBack()
        model.navigateBack()
        XCTAssertEqual(model.currentNode?.id, folderURL.path)
        XCTAssertEqual(model.navigationPath.count, 1)
        XCTAssertEqual(model.result?.root.children.count, 0)
    }

    func testRemovingFolderPrunesItsHistoryWithoutTouchingOtherPages() async throws {
        let model = try await makeModel()
        model.showAICodingTools()
        try await openFolder(in: model)
        model.showDeveloperStorage()
        model.removeSessionFolder(SessionFolder(url: folderURL))
        model.navigateBack()
        XCTAssertEqual(model.selectedSection, .aiCodingTools)
        XCTAssertNil(model.cachedResult(at: folderURL))
        XCTAssertTrue(model.sessionFolders.isEmpty)
    }

    private func makeModel(scanner: NavigationTestScanner = NavigationTestScanner()) async throws -> AppViewModel {
        let model = AppViewModel(
            scanner: scanner,
            fullDiskAccessChecker: FullDiskAccessChecker(accessProbe: { true })
        )
        try await waitUntil { !model.isDiscoveringVolumes }
        return model
    }

    private func openFolder(in model: AppViewModel) async throws {
        model.inspectAICodingNode(NavigationTestScanner.result(at: folderURL).root)
        try await waitUntil { !model.isScanning }
        XCTAssertEqual(model.result?.root.id, folderURL.path)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for navigation fixture")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

private actor NavigationTestScanner: VolumeScanning {
    private var blocked = false
    private var includesFolders = true
    private(set) var calls = 0

    func setBlocked(_ value: Bool) { blocked = value }
    func setIncludesFolders(_ value: Bool) { includesFolders = value }

    func scan(url: URL, onProgress: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        calls += 1
        while blocked { try await Task.sleep(nanoseconds: 2_000_000) }
        return Self.result(at: url, includesFolders: includesFolders)
    }

    nonisolated static func result(at url: URL, includesFolders: Bool = true) -> ScanResult {
        let leaf = FileNodeSnapshot(
            name: "file", size: 10, isDirectory: false, isReadable: true, children: [], itemCount: 1
        )
        let grandchild = FileNodeSnapshot(
            name: "grandchild", size: 10, isDirectory: true, isReadable: true, children: [leaf], itemCount: 2
        )
        let child = FileNodeSnapshot(
            name: "child", size: 10, isDirectory: true, isReadable: true, children: [grandchild], itemCount: 3
        )
        let root = FileNode(rootURL: url, snapshot: FileNodeSnapshot(
            name: url.lastPathComponent, size: 10, isDirectory: true, isReadable: true,
            children: includesFolders ? [child] : [], itemCount: 4
        ))
        return ScanResult(root: root, duration: 1, itemsScanned: 4, unreadableItems: 0)
    }
}
