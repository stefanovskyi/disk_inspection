import Foundation
import XCTest
@testable import SpaceLens

final class AIModelsAndRuntimesAnalyzerTests: XCTestCase {
    func testOllamaManifestsProduceModelsAndSharedBlobIsMeasuredOnce() async throws {
        let root = temporaryDirectory(named: "Ollama")
        defer { try? FileManager.default.removeItem(at: root) }

        let modelRoot = root.appendingPathComponent("models", isDirectory: true)
        let blobRoot = modelRoot.appendingPathComponent("blobs", isDirectory: true)
        let manifestRoot = modelRoot.appendingPathComponent(
            "manifests/registry.ollama.ai/library/example",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: blobRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifestRoot, withIntermediateDirectories: true)

        let digest = String(repeating: "a", count: 64)
        let blob = blobRoot.appendingPathComponent("sha256-\(digest)")
        try minimalGGUF().write(to: blob)
        let manifest = """
        {
          "layers": [
            {
              "mediaType": "application/vnd.ollama.image.model",
              "digest": "sha256:\(digest)",
              "size": 24
            }
          ]
        }
        """
        try Data(manifest.utf8).write(to: manifestRoot.appendingPathComponent("latest"))
        try Data(manifest.utf8).write(to: manifestRoot.appendingPathComponent("q4"))

        let discovery = AIModelsDiscoveryResult(
            roots: [
                .init(
                    runtimeID: .ollama,
                    name: "Ollama fixture",
                    url: root,
                    purpose: .managed,
                    modelRoot: modelRoot
                )
            ],
            installations: [:]
        )
        let report = try await AIModelsAndRuntimesAnalyzer(discovery: discovery).analyze(
            request: fixtureRequest(home: root)
        )
        let ollama = try XCTUnwrap(report.runtimes.first { $0.id == .ollama })

        XCTAssertEqual(ollama.models.map(\.displayName).sorted(), ["example:latest", "example:q4"])
        XCTAssertTrue(ollama.models.allSatisfy { $0.format == .gguf })
        XCTAssertTrue(ollama.models.allSatisfy { $0.sharedBytes > 0 })
        let weightSize = ollama.categories.first { $0.category == .weights }?.size ?? 0
        XCTAssertGreaterThan(weightSize, 0)
        XCTAssertLessThan(weightSize, ollama.models.reduce(0) { $0 + $1.allocatedSize })
    }

    func testStandaloneSearchRejectsExtensionOnlyFalsePositive() async throws {
        let root = temporaryDirectory(named: "Standalone")
        defer { try? FileManager.default.removeItem(at: root) }

        try minimalGGUF().write(to: root.appendingPathComponent("real-model-Q4_K_M.gguf"))
        try Data("not a model".utf8).write(to: root.appendingPathComponent("renamed-download.gguf"))
        let discovery = AIModelsDiscoveryResult(
            roots: [
                .init(
                    runtimeID: .standalone,
                    name: "Fixture models",
                    url: root,
                    purpose: .standaloneSearch
                )
            ],
            installations: [:]
        )

        let report = try await AIModelsAndRuntimesAnalyzer(discovery: discovery).analyze(
            request: fixtureRequest(home: root)
        )
        let standalone = try XCTUnwrap(report.runtimes.first { $0.id == .standalone })

        XCTAssertEqual(standalone.models.count, 1)
        XCTAssertEqual(standalone.models[0].displayName, "real-model-Q4_K_M")
        XCTAssertEqual(standalone.models[0].quantization, "Q4_K_M")
        XCTAssertEqual(standalone.locations.count, 1)
        XCTAssertEqual(standalone.locations[0].itemCount, 1)
    }

    func testDiscoveryHonorsLMStudioPointerAndEnvironmentOverrides() throws {
        let home = temporaryDirectory(named: "Discovery")
        defer { try? FileManager.default.removeItem(at: home) }
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let lmHome = home.appendingPathComponent("custom-lm-home", isDirectory: true)
        let ollamaModels = home.appendingPathComponent("custom-ollama", isDirectory: true)
        let hub = home.appendingPathComponent("custom-hub", isDirectory: true)
        for directory in [appSupport, lmHome, ollamaModels, hub] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(lmHome.path.utf8).write(to: home.appendingPathComponent(".lmstudio-home-pointer"))

        let request = AIModelsAndRuntimesRequest(
            homeDirectory: home,
            applicationSupportDirectory: appSupport,
            environment: [
                "OLLAMA_MODELS": ollamaModels.path,
                "HF_HUB_CACHE": hub.path
            ]
        )
        let discovery = AIModelsDiscovery.discover(request: request)

        XCTAssertEqual(AIModelsDiscovery.lmStudioHome(request: request), lmHome.standardizedFileURL)
        XCTAssertTrue(discovery.roots.contains {
            $0.runtimeID == .lmStudio && $0.url.standardizedFileURL == lmHome.standardizedFileURL
        })
        XCTAssertTrue(discovery.roots.contains {
            $0.runtimeID == .ollama && $0.modelRoot?.standardizedFileURL == ollamaModels.standardizedFileURL
        })
        XCTAssertTrue(discovery.roots.contains {
            $0.runtimeID == .huggingFace && $0.url.standardizedFileURL == hub.standardizedFileURL
        })
    }

    func testDiscoveryFallsBackToBothExistingLMStudioHomesForInvalidPointer() throws {
        let home = temporaryDirectory(named: "LMStudioFallback")
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = home.appendingPathComponent(".cache/lm-studio", isDirectory: true)
        let current = home.appendingPathComponent(".lmstudio", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("relative/path".utf8).write(to: home.appendingPathComponent(".lmstudio-home-pointer"))
        let request = fixtureRequest(home: home)

        let discovery = AIModelsDiscovery.discover(request: request)
        let lmHomes = Set(discovery.roots.filter { $0.runtimeID == .lmStudio }.map { $0.url.path })

        XCTAssertEqual(AIModelsDiscovery.lmStudioHome(request: request), legacy.standardizedFileURL)
        XCTAssertTrue(lmHomes.contains(legacy.path))
        XCTAssertTrue(lmHomes.contains(current.path))
    }

    func testDiscoveryRecognizesVerifiedLlamaCppSourceBuild() throws {
        let home = temporaryDirectory(named: "LlamaCpp")
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent("llama.cpp", isDirectory: true)
        let command = source.appendingPathComponent("build/bin/llama-cli")
        try FileManager.default.createDirectory(
            at: command.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("project(llama)".utf8).write(to: source.appendingPathComponent("CMakeLists.txt"))
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: command)

        let discovery = AIModelsDiscovery.discover(request: fixtureRequest(home: home))
        let installations = discovery.installations[.llamaCpp, default: []]

        XCTAssertTrue(installations.contains {
            $0.kind == .sourceBuild && $0.url.standardizedFileURL == command.deletingLastPathComponent()
        })
    }

    func testSafeTensorsValidationChecksBoundedJSONHeader() throws {
        let root = temporaryDirectory(named: "SafeTensors")
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appendingPathComponent("valid.safetensors")
        let invalid = root.appendingPathComponent("invalid.safetensors")
        let header = Data("{\"weight\":{\"dtype\":\"F16\",\"shape\":[1],\"data_offsets\":[0,2]}}".utf8)
        var data = Data()
        appendLittleEndian(UInt64(header.count), to: &data)
        data.append(header)
        data.append(contentsOf: [0, 0])
        try data.write(to: valid)
        try Data("extension is not evidence".utf8).write(to: invalid)

        XCTAssertTrue(AIModelInventoryParsers.isSafeTensors(at: valid))
        XCTAssertFalse(AIModelInventoryParsers.isSafeTensors(at: invalid))
    }

    private func fixtureRequest(home: URL) -> AIModelsAndRuntimesRequest {
        AIModelsAndRuntimesRequest(
            homeDirectory: home,
            applicationSupportDirectory: home.appendingPathComponent("Library/Application Support"),
            environment: [:]
        )
    }

    private func temporaryDirectory(named name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpaceLens-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func minimalGGUF() -> Data {
        var data = Data([0x47, 0x47, 0x55, 0x46])
        appendLittleEndian(UInt32(3), to: &data)
        appendLittleEndian(UInt64(0), to: &data)
        appendLittleEndian(UInt64(0), to: &data)
        return data
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
