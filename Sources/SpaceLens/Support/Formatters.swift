import Foundation

enum StorageFormatters {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func bytes(_ count: Int64) -> String {
        guard count > 0 else { return "0 bytes" }
        return byteFormatter.string(fromByteCount: count)
    }

    static func duration(_ interval: TimeInterval) -> String {
        if interval < 1 { return "under a second" }
        if interval < 60 { return "\(Int(interval.rounded())) sec" }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return "\(minutes) min \(seconds) sec"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(fraction < 0.01 ? 1 : 0)))
    }
}
