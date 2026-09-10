import SwiftUI
struct AICodingToolRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let tool: AICodingToolReport
    let totalSize: Int64
    let isSelected: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let fraction = totalSize > 0 ? Double(tool.size) / Double(totalSize) : 0

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(toolSubtitle)
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(StorageFormatters.bytes(tool.size))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.primaryText)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.elevatedSurface)
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: max(tool.size > 0 ? 3 : 0, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? theme.selectionSurface : Color.clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(theme.selectionBorder, lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(tool.displayName), \(StorageFormatters.bytes(tool.size)), \(toolSubtitle)"
        )
    }

    private var toolSubtitle: String {
        if tool.issueCount > 0 { return "\(tool.issueCount) location issues" }
        if !tool.hasMeasuredStorage { return "Storage not found" }
        return "\(tool.itemCount.formatted()) items"
    }
}
