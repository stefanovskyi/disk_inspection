import Foundation

struct AIModelRuntimeID: Hashable, Identifiable, RawRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }

    static let ollama = Self(rawValue: "ollama")
    static let lmStudio = Self(rawValue: "lm-studio")
    static let llamaCpp = Self(rawValue: "llama-cpp")
    static let huggingFace = Self(rawValue: "hugging-face")
    static let standalone = Self(rawValue: "standalone")
}

struct AIModelRuntimeMetadata: Identifiable, Equatable, Sendable {
    let id: AIModelRuntimeID
    let displayName: String
    let systemImage: String
    let emptyDescription: String
}

enum AIModelsCatalog {
    static let supportedRuntimes: [AIModelRuntimeMetadata] = [
        .init(
            id: .ollama,
            displayName: "Ollama",
            systemImage: "shippingbox.fill",
            emptyDescription: "No Ollama models were found in the resolved model store."
        ),
        .init(
            id: .lmStudio,
            displayName: "LM Studio",
            systemImage: "macwindow",
            emptyDescription: "No GGUF or MLX models were found in the resolved LM Studio home."
        ),
        .init(
            id: .llamaCpp,
            displayName: "llama.cpp / CLI",
            systemImage: "terminal.fill",
            emptyDescription: "llama.cpp loads arbitrary GGUF paths; models remain attributed to their storage manager."
        ),
        .init(
            id: .huggingFace,
            displayName: "Hugging Face Hub",
            systemImage: "externaldrive.badge.icloud",
            emptyDescription: "No cached model repositories were found in the resolved Hub cache."
        ),
        .init(
            id: .standalone,
            displayName: "Standalone Models",
            systemImage: "doc.badge.gearshape",
            emptyDescription: "No standalone model files were found in the selected search folders."
        )
    ]

    static func metadata(for id: AIModelRuntimeID) -> AIModelRuntimeMetadata {
        supportedRuntimes.first { $0.id == id }
            ?? .init(id: id, displayName: id.rawValue, systemImage: "cpu", emptyDescription: "No models found.")
    }
}

enum AIModelStorageCategory: String, CaseIterable, Identifiable, Sendable {
    case weights
    case manifests
    case logs
    case chats
    case runtimes
    case applicationState
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weights: "Model weights"
        case .manifests: "Manifests & presets"
        case .logs: "Logs & diagnostics"
        case .chats: "Chats & databases"
        case .runtimes: "Inference runtimes"
        case .applicationState: "UI caches & app state"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .weights: "shippingbox"
        case .manifests: "doc.text"
        case .logs: "waveform.path.ecg"
        case .chats: "bubble.left.and.bubble.right"
        case .runtimes: "cpu"
        case .applicationState: "internaldrive"
        case .other: "tray.full"
        }
    }
}

struct AIModelCategoryBreakdown: Identifiable, Equatable, Sendable {
    let category: AIModelStorageCategory
    let size: Int64
    let itemCount: Int

    var id: String { category.id }
}

enum AIModelFormat: String, Equatable, Sendable {
    case gguf
    case mlx
    case safetensors
    case unknown

    var displayName: String {
        switch self {
        case .gguf: "GGUF"
        case .mlx: "Apple Silicon MLX"
        case .safetensors: "SafeTensors"
        case .unknown: "Format unknown"
        }
    }
}

enum AIModelInstallationKind: String, Equatable, Sendable {
    case application
    case commandLine
    case homebrew
    case sourceBuild

    var displayName: String {
        switch self {
        case .application: "Native app"
        case .commandLine: "CLI"
        case .homebrew: "Homebrew"
        case .sourceBuild: "Source build"
        }
    }

    var systemImage: String {
        switch self {
        case .application: "macwindow"
        case .commandLine: "terminal"
        case .homebrew: "shippingbox"
        case .sourceBuild: "hammer"
        }
    }
}

struct AIModelRuntimeInstallation: Identifiable, Equatable, Sendable {
    let runtimeID: AIModelRuntimeID
    let name: String
    let kind: AIModelInstallationKind
    let url: URL
    let version: String?

    var id: String { "\(runtimeID.rawValue)|\(kind.rawValue)|\(url.standardizedFileURL.path)" }
}

enum AIModelLocationStatus: String, Equatable, Sendable {
    case measured
    case unreadable
    case stalled
    case linked

    var displayName: String {
        switch self {
        case .measured: "Measured"
        case .unreadable: "Partly unreadable"
        case .stalled: "Scan timed out"
        case .linked: "Linked location skipped"
        }
    }

    var isIssue: Bool { self != .measured }
}

struct AIModelStorageLocation: Identifiable, Equatable, Sendable {
    let runtimeID: AIModelRuntimeID
    let name: String
    let url: URL
    let size: Int64
    let itemCount: Int
    let latestModificationDate: Date?
    let status: AIModelLocationStatus
    let root: FileNode?

    var id: String { "\(runtimeID.rawValue)|\(url.standardizedFileURL.path)" }
}

struct AIModelRecord: Identifiable, Equatable, Sendable {
    let id: String
    let runtimeID: AIModelRuntimeID
    let displayName: String
    let format: AIModelFormat
    let quantization: String?
    let allocatedSize: Int64
    let sharedBytes: Int64
    let primaryURL: URL
    let latestModificationDate: Date?
    let digest: String?
    let contentDigests: [String]
    let duplicateDescription: String?

    init(
        id: String,
        runtimeID: AIModelRuntimeID,
        displayName: String,
        format: AIModelFormat,
        quantization: String? = nil,
        allocatedSize: Int64,
        sharedBytes: Int64 = 0,
        primaryURL: URL,
        latestModificationDate: Date? = nil,
        digest: String? = nil,
        contentDigests: [String] = [],
        duplicateDescription: String? = nil
    ) {
        self.id = id
        self.runtimeID = runtimeID
        self.displayName = displayName
        self.format = format
        self.quantization = quantization
        self.allocatedSize = allocatedSize
        self.sharedBytes = sharedBytes
        self.primaryURL = primaryURL.standardizedFileURL
        self.latestModificationDate = latestModificationDate
        self.digest = digest
        self.contentDigests = Array(Set(contentDigests.map { $0.lowercased() })).sorted()
        self.duplicateDescription = duplicateDescription
    }

    var subtitle: String {
        var parts = [format.displayName]
        if let quantization, !quantization.isEmpty { parts.append(quantization) }
        if sharedBytes > 0 { parts.append("\(StorageFormatters.bytes(sharedBytes)) shared") }
        if let digest, !digest.isEmpty {
            parts.append("Digest \(digest.prefix(12))…")
        } else {
            parts.append(primaryURL.path)
        }
        return parts.joined(separator: " · ")
    }

    func withDuplicateDescription(_ description: String?) -> Self {
        Self(
            id: id,
            runtimeID: runtimeID,
            displayName: displayName,
            format: format,
            quantization: quantization,
            allocatedSize: allocatedSize,
            sharedBytes: sharedBytes,
            primaryURL: primaryURL,
            latestModificationDate: latestModificationDate,
            digest: digest,
            contentDigests: contentDigests,
            duplicateDescription: description
        )
    }
}

struct AIModelRuntimeReport: Identifiable, Equatable, Sendable {
    let runtime: AIModelRuntimeMetadata
    let models: [AIModelRecord]
    let installations: [AIModelRuntimeInstallation]
    let locations: [AIModelStorageLocation]
    let categories: [AIModelCategoryBreakdown]

    var id: AIModelRuntimeID { runtime.id }
    var displayName: String { runtime.displayName }
    var systemImage: String { runtime.systemImage }
    var size: Int64 { locations.reduce(0) { safeAdd($0, $1.size) } }
    var itemCount: Int { locations.reduce(0) { safeAdd($0, $1.itemCount) } }
    var issueCount: Int { locations.filter { $0.status.isIssue }.count }
    var latestModificationDate: Date? { locations.compactMap(\.latestModificationDate).max() }

    var countDescription: String {
        switch id {
        case .llamaCpp:
            let count = installations.count
            return "\(count) " + (count == 1 ? "installation" : "installations")
        case .huggingFace:
            let count = models.count
            return "\(count) cached model " + (count == 1 ? "repo" : "repos")
        case .standalone:
            let count = models.count
            return "\(count) loose " + (count == 1 ? "model" : "models")
        default:
            let count = models.count
            return "\(count) " + (count == 1 ? "model" : "models")
        }
    }
}

struct AIModelsAndRuntimesReport: Equatable, Sendable {
    let runtimes: [AIModelRuntimeReport]
    let startedAt: Date
    let completedAt: Date
    let duration: TimeInterval

    init(runtimes: [AIModelRuntimeReport], startedAt: Date, completedAt: Date = Date()) {
        self.runtimes = runtimes
        self.startedAt = startedAt
        self.completedAt = completedAt
        duration = max(completedAt.timeIntervalSince(startedAt), 0)
    }

    var rankedRuntimes: [AIModelRuntimeReport] {
        runtimes.sorted { left, right in
            if left.size == right.size {
                return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
            }
            return left.size > right.size
        }
    }

    var totalSize: Int64 { runtimes.reduce(0) { safeAdd($0, $1.size) } }
    var modelCount: Int { runtimes.reduce(0) { safeAdd($0, $1.models.count) } }
    var itemCount: Int { runtimes.reduce(0) { safeAdd($0, $1.itemCount) } }
    var issueCount: Int { runtimes.reduce(0) { safeAdd($0, $1.issueCount) } }
}

struct AIModelsProgress: Equatable, Sendable {
    var currentRuntime: AIModelRuntimeMetadata?
    var currentLocationName: String?
    var currentPath: String?
    var completedLocations = 0
    var totalLocations = 0
    var itemsScanned = 0
    var mappedBytes: Int64 = 0

    var fractionCompleted: Double? {
        guard totalLocations > 0 else { return nil }
        return min(max(Double(completedLocations) / Double(totalLocations), 0), 1)
    }
}

enum AIModelsAnalysisState: Equatable, Sendable {
    case idle
    case running(previousReport: AIModelsAndRuntimesReport?)
    case completed(AIModelsAndRuntimesReport)
    case failed(message: String, previousReport: AIModelsAndRuntimesReport?)

    var report: AIModelsAndRuntimesReport? {
        switch self {
        case .idle: nil
        case .running(let report): report
        case .completed(let report): report
        case .failed(_, let report): report
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

private func safeAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int64.max : result.partialValue
}

private func safeAdd(_ left: Int, _ right: Int) -> Int {
    let result = left.addingReportingOverflow(right)
    return result.overflow ? Int.max : result.partialValue
}
