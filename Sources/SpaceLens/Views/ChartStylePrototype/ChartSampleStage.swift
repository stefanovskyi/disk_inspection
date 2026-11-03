import SwiftUI

/// Invented sample data around the production chart, for appearance and interaction checks.
struct ChartSampleStage: View {
    @Environment(\.colorScheme) private var colorScheme
    let root: FileNode
    let volume: VolumeInfo?
    var selectedItemID: String? = nil
    var actions: SunburstChartActions = .disabled

    private var dark: Bool { colorScheme == .dark }
    private var theme: SpaceTheme { SpaceTheme(colorScheme: colorScheme) }
    private var accent: Color { HoloPulseStyle.accent(isDark: dark) }

    var body: some View {
        HStack(spacing: 12) {
            StorageMapPanel(node: root, volume: volume, isProvisional: false,
                            selectedItemID: selectedItemID, actions: actions)
            directoryPanel.padding(.horizontal, 20).spacePanel()
        }
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
        let color = HoloPulseStyle.color(hue: HoloPulseStyle.branchHue(at: index),
                                  depth: 0, isDark: dark)
        return Button {
            if child.isDirectory && !child.children.isEmpty { actions.inspect(child) }
            else { actions.select(child) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(dark ? color : theme.secondaryText)
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
