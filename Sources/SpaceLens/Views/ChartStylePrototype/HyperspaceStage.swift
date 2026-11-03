import SwiftUI

struct HyperspaceStage: View {
    @Environment(\.colorScheme) private var colorScheme
    let variant: HyperspaceVariant
    let root: FileNode
    let volume: VolumeInfo?
    var selectedItemID: String? = nil
    var actions: SunburstChartActions = .disabled

    private var dark: Bool { colorScheme == .dark }
    private var theme: SpaceTheme { SpaceTheme(colorScheme: colorScheme) }
    private var accent: Color { variant.accent(isDark: dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                        Text("SPACELENS / HYPERSPACE").tracking(3)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    Text(variant.subtitle)
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text(variant.title.uppercased()).tracking(1.5)
                    Text("SAMPLE DATA").foregroundStyle(theme.tertiaryText)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(accent)
            }
            .padding(24)

            Rectangle().fill(accent.opacity(0.35)).frame(height: 1)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                SunburstChart(root: root, volume: volume, isProvisional: false,
                              selectedItemID: selectedItemID, actions: actions)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                directoryPanel.padding(.trailing, 24)
            }

            HStack {
                Image(systemName: "cursorarrow.rays")
                Text("\(variant.hoverHint) · settles after 1.2 seconds")
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(variant.background(isDark: dark))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.35), lineWidth: 1) }
        .environment(\.hyperspaceVariant, variant)
    }

    private var directoryPanel: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("SECTOR DIRECTORY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(accent)
            Text(root.name)
                .font(.title3.weight(.medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            ForEach(Array(root.sortedChildren.prefix(6).enumerated()), id: \.element.id) { index, child in
                directory(child, index: index)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 9) {
                Text("\(StorageFormatters.bytes(root.size)) MAPPED")
                if let volume { Text("\(StorageFormatters.bytes(volume.availableCapacity)) FREE") }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.07))
            .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        }
        .frame(width: 220)
        .padding(.vertical, 22)
    }

    private func directory(_ child: FileNode, index: Int) -> some View {
        let color = variant.color(hue: HyperspaceVariant.branchHues[index % HyperspaceVariant.branchHues.count],
                                  depth: 0, isDark: dark)
        return Button {
            if child.isDirectory && !child.children.isEmpty { actions.inspect(child) }
            else { actions.select(child) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(color)
                    Text(child.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(StorageFormatters.percent(child.percentage(of: root.size)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
                Text(StorageFormatters.bytes(child.size))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                GeometryReader { proxy in
                    Rectangle().fill(color.opacity(0.65))
                        .frame(width: max(3, proxy.size.width * child.percentage(of: root.size)))
                }
                .frame(height: 2)
            }
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Inspect \(child.name), \(StorageFormatters.bytes(child.size))")
    }
}
