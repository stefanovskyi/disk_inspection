import Foundation

/// Serializes the memory-heavy retained summary construction and archive write
/// while allowing completed in-memory scan results to be installed immediately.
actor ScanResultFinalizer {
    private let store: PreviousScanStore

    init(store: PreviousScanStore = PreviousScanStore()) {
        self.store = store
    }

    func finalize(_ result: ScanResult, for volume: VolumeInfo) -> PreviousScanSummary {
        let summary = PreviousScanSummary(result: result, volume: volume)
        try? store.store(summary)
        return summary
    }
}
