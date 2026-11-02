import SwiftUI

/// Original space-console concepts, using the real SpaceLens chart and sample data.
struct SpaceChartStage: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: ChartPrototypeStyle
    let root: FileNode
    let volume: VolumeInfo?
    let selectedItemID: String?
    let actions: SunburstChartActions

    private var dark: Bool { colorScheme == .dark }
    private var theme: SpaceTheme { SpaceTheme(colorScheme: colorScheme) }
    private var accent: Color { style.spaceAccent(isDark: dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: style == .bridge ? "command.square" : "scope")
                        Text("SPACELENS / \(style.title.uppercased())")
                            .tracking(3)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    Text(style.subtitle)
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text("STORAGE MAP / 01")
                        .tracking(1.5)
                    Text("SAMPLE DATA")
                        .foregroundStyle(theme.tertiaryText)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(accent)
            }
            .padding(24)

            Rectangle().fill(accent.opacity(0.35)).frame(height: 1)
                .padding(.horizontal, 24)

            if style == .lasers {
                HStack(spacing: 20) {
                    Text("ENERGY TRACE / HOVER TO TARGET")
                        .tracking(1.2)
                    Spacer()
                    Text("SIZE / BYTES · DEPTH / RINGS")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                chart.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 16) {
                    ForEach(Array(root.sortedChildren.prefix(5).enumerated()), id: \.element.id) { index, child in
                        directory(child, index: index, compact: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                HStack(spacing: 12) {
                    if style == .bridge { directoryPanel.padding(.leading, 24) }
                    chart.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if style != .bridge { directoryPanel.padding(.trailing, 24) }
                }
            }

            HStack {
                Image(systemName: "cursorarrow.rays")
                Text(style.tradeoff)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(style.spaceBackground(isDark: dark))
        .clipShape(RoundedRectangle(cornerRadius: style == .bridge ? 26 : 12))
        .overlay {
            RoundedRectangle(cornerRadius: style == .bridge ? 26 : 12)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        }
        .environment(\.chartPrototypeStyle, style)
    }

    private var chart: some View {
        SunburstChart(root: root, volume: volume, isProvisional: false,
                      selectedItemID: selectedItemID, actions: actions)
            .padding(14)
    }

    private var directoryPanel: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text(style == .bridge ? "DIRECTORY / ACCESS" : "SECTOR DIRECTORY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(accent)
            Text(root.name)
                .font(.title3.weight(.medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            ForEach(Array(root.sortedChildren.prefix(6).enumerated()), id: \.element.id) { index, child in
                directory(child, index: index, compact: false)
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 9) {
                Text("\(StorageFormatters.bytes(root.size)) MAPPED")
                if let volume {
                    Text("\(StorageFormatters.bytes(volume.availableCapacity)) FREE")
                }
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

    private func directory(_ child: FileNode, index: Int, compact: Bool) -> some View {
        let color = style.color(hue: style.branchHues[index % style.branchHues.count], depth: 0, isDark: dark)
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
                    if !compact {
                        Spacer(minLength: 0)
                        Text(StorageFormatters.percent(child.percentage(of: root.size)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Text(StorageFormatters.bytes(child.size))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: style == .bridge ? 4 : 0)
                        .fill(color.opacity(style == .bridge ? 0.9 : 0.65))
                        .frame(width: max(3, proxy.size.width * child.percentage(of: root.size)))
                }
                .frame(height: style == .bridge ? 7 : 2)
            }
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Inspect \(child.name), \(StorageFormatters.bytes(child.size))")
    }
}
