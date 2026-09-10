import SwiftUI

struct AICodingToolsToolbarStatus: View {
    let progress: AICodingToolsProgress

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(toolbarText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing AI coding tools, \(toolbarText)")
    }

    private var toolbarText: String {
        if let tool = progress.currentTool {
            return "\(tool.displayName) · \(StorageFormatters.bytes(progress.mappedBytes))"
        }
        return "Preparing…"
    }
}
