import Foundation

enum ScanEverythingAnalysis: String, CaseIterable, Hashable, Sendable {
    case aiCodingTools
    case aiModelsAndRuntimes
    case developerStorage

    var title: String {
        switch self {
        case .aiCodingTools: "AI Coding Tools"
        case .aiModelsAndRuntimes: "AI Models"
        case .developerStorage: "Developer Storage"
        }
    }
}

enum ScanEverythingStep: Equatable, Sendable, Identifiable {
    case volume(VolumeInfo)
    case analysis(ScanEverythingAnalysis)

    var id: String {
        switch self {
        case .volume(let volume): "volume:\(volume.persistentIdentifier)"
        case .analysis(let analysis): "analysis:\(analysis.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .volume(let volume): "Scanning \(volume.name)"
        case .analysis(let analysis): "Analyzing \(analysis.title)"
        }
    }
}

/// An immutable snapshot of the work selected when Scan Everything begins.
struct ScanEverythingPlan: Equatable, Sendable {
    let volumes: [VolumeInfo]
    let analyses: [ScanEverythingAnalysis]

    init(
        volumes: [VolumeInfo],
        analyses: [ScanEverythingAnalysis] = ScanEverythingAnalysis.allCases
    ) {
        var seenVolumes: Set<String> = []
        self.volumes = volumes
            .filter(\.isLocal)
            .filter { seenVolumes.insert($0.persistentIdentifier).inserted }
            .sorted(by: Self.volumeOrder)

        var seenAnalyses: Set<ScanEverythingAnalysis> = []
        self.analyses = analyses.filter { seenAnalyses.insert($0).inserted }
    }

    var steps: [ScanEverythingStep] {
        volumes.map(ScanEverythingStep.volume)
            + analyses.map(ScanEverythingStep.analysis)
    }

    var includesStartupVolume: Bool {
        volumes.contains(where: \.isStartupVolume)
    }

    private static func volumeOrder(_ left: VolumeInfo, _ right: VolumeInfo) -> Bool {
        if left.isStartupVolume != right.isStartupVolume { return left.isStartupVolume }
        if left.isExternal != right.isExternal { return !left.isExternal }
        let nameOrder = left.name.localizedStandardCompare(right.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return left.url.standardizedFileURL.path < right.url.standardizedFileURL.path
    }
}

struct ScanEverythingOperationProgress: Equatable, Sendable {
    let step: ScanEverythingStep
    var currentLocationName: String?
    var currentPath: String?
    var itemsScanned = 0
    var mappedBytes: Int64 = 0
    var fraction: Double?
}

struct ScanEverythingProgress: Equatable, Sendable {
    var activeOperations: [ScanEverythingStep.ID: ScanEverythingOperationProgress]
    var completedStepIDs: Set<ScanEverythingStep.ID>
    let totalSteps: Int
    var overallFraction: Double

    init(
        activeOperations: [ScanEverythingStep.ID: ScanEverythingOperationProgress] = [:],
        completedStepIDs: Set<ScanEverythingStep.ID> = [],
        totalSteps: Int,
        overallFraction: Double = 0
    ) {
        self.activeOperations = activeOperations
        self.completedStepIDs = completedStepIDs
        self.totalSteps = totalSteps
        self.overallFraction = min(max(overallFraction, 0), 1)
    }

    func operation(for step: ScanEverythingStep) -> ScanEverythingOperationProgress? {
        activeOperations[step.id]
    }

    var activeVolumeCount: Int {
        activeOperations.values.count {
            if case .volume = $0.step { return true }
            return false
        }
    }

    var activeOperationsInStableOrder: [ScanEverythingOperationProgress] {
        activeOperations.values.sorted { $0.step.id < $1.step.id }
    }
}

enum ScanEverythingStepStatus: Equatable, Sendable {
    case completed
    case failed(message: String)
}

struct ScanEverythingStepOutcome: Equatable, Sendable {
    let step: ScanEverythingStep
    let duration: TimeInterval
    let status: ScanEverythingStepStatus
}

struct ScanEverythingSummary: Equatable, Sendable {
    let startedAt: Date
    let duration: TimeInterval
    let outcomes: [ScanEverythingStepOutcome]

    var completedCount: Int {
        outcomes.count { $0.status == .completed }
    }

    var failureCount: Int {
        outcomes.count - completedCount
    }
}

enum ScanEverythingState: Equatable, Sendable {
    case idle
    case running(startedAt: Date, progress: ScanEverythingProgress)
    case completed(ScanEverythingSummary)
    case cancelled

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var progress: ScanEverythingProgress? {
        guard case .running(_, let progress) = self else { return nil }
        return progress
    }

    var startedAt: Date? {
        guard case .running(let startedAt, _) = self else { return nil }
        return startedAt
    }

    var summary: ScanEverythingSummary? {
        guard case .completed(let summary) = self else { return nil }
        return summary
    }
}
