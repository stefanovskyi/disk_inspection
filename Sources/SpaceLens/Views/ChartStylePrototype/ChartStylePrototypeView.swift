import AppKit
import SwiftUI

// Prototype only. Run `make chart-preview`; no filesystem scan or persisted settings.
struct ChartStylePrototypeView: View {
    @State private var style = ChartPrototypeStyle.aurora
    @State private var lightAppearance = false
    @State private var compactDataset = false
    @State private var path = [ChartPrototypeData.disk]
    @State private var selectedItem: FileNode?

    private var root: FileNode { path.last ?? ChartPrototypeData.disk }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Label("SpaceLens · Chart style lab", systemImage: "circle.hexagongrid")
                    .font(.headline)
                Spacer()
                Picker("Sample", selection: $compactDataset) {
                    Text("Disk · deep hierarchy").tag(false)
                    Text("Folder · shallow hierarchy").tag(true)
                }
                .labelsHidden()
                .frame(width: 260)
                Picker("Appearance", selection: $lightAppearance) {
                    Text("Dark").tag(false)
                    Text("Light").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(18)

            HStack(spacing: 5) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption2) }
                    Button(node.name) {
                        path = Array(path.prefix(index + 1))
                        selectedItem = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(index == path.count - 1 ? .semibold : .regular))
                }
                Spacer()
                Text("Sample data · hover, click folders, or select a row")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)

            ChartStylePrototypeStage(
                style: style, root: root,
                volume: !compactDataset && path.count == 1 ? ChartPrototypeData.volume : nil,
                selectedItemID: selectedItem?.id,
                actions: SunburstChartActions(
                    select: { selectedItem = $0 },
                    inspect: { path.append($0); selectedItem = nil },
                    inspectSmallerItems: { selectedItem = $0.parent },
                    showInFinder: { _ in }, openInTerminal: { _ in }
                )
            )
            .padding(.horizontal, 18)

            HStack(spacing: 14) {
                Button { style = style.shifted(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous style")
                .keyboardShortcut(.leftArrow, modifiers: [])
                Picker("Prototype", selection: $style) {
                    ForEach(ChartPrototypeStyle.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                Button { style = style.shifted(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next style")
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(12)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 12)

            Text("Design prototype · identical byte proportions and depth · Finder and Terminal actions are inactive for sample data")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
        .background(SpaceTheme(colorScheme: lightAppearance ? .light : .dark).background)
        .preferredColorScheme(lightAppearance ? .light : .dark)
        .onChange(of: compactDataset) { _, compact in
            path = [compact ? ChartPrototypeData.folder : ChartPrototypeData.disk]
            selectedItem = nil
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--export-chart-previews"),
               arguments.indices.contains(index + 1) {
                do {
                    try ChartPrototypeExporter.export(to: URL(fileURLWithPath: arguments[index + 1]))
                    NSApplication.shared.terminate(nil)
                } catch {
                    fputs("Chart prototype export failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
    }
}

struct ChartStylePrototypeStage: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: ChartPrototypeStyle
    let root: FileNode
    let volume: VolumeInfo?
    var selectedItemID: String? = nil
    var actions: SunburstChartActions = .disabled

    private var theme: SpaceTheme { SpaceTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(style == .classic ? "Storage map · Original" : "Storage map · \(style.title)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(style.subtitle)
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Text("SAMPLE DATA")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.top, 5)
            }
            .padding(22)

            if style == .prism {
                HStack(spacing: 35) {
                    metric("USED", value: StorageFormatters.bytes(root.size))
                    if let volume {
                        metric("FREE", value: StorageFormatters.bytes(volume.availableCapacity))
                    }
                    metric("HIERARCHY", value: "Up to 6 rings")
                    Spacer()
                }
                .padding(.horizontal, 24)
                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 12) {
                    ForEach(Array(root.sortedChildren.prefix(5).enumerated()), id: \.element.id) { index, child in
                        branchRow(child, index: index, compact: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            } else if style == .contour {
                HStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("DIRECTORIES")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(theme.tertiaryText)
                        branchList
                        Spacer(minLength: 0)
                        Text("One band = one level deeper.\nEmpty space = no descendant.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(width: 225)
                    .padding(.leading, 24)
                    .padding(.vertical, 24)
                    chart
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 12) {
                    chart
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: 22) {
                        metric("CURRENT LOCATION", value: root.name)
                        Text("Largest folders")
                            .font(.headline)
                            .foregroundStyle(theme.primaryText)
                        branchList
                        Spacer(minLength: 0)
                        Label("Explore one layer at a time", systemImage: "cursorarrow.click")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(width: 235)
                    .padding(.trailing, 24)
                    .padding(.vertical, 24)
                }
            }

            Text(style.tradeoff)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(theme.border.opacity(0.7), lineWidth: 1)
        }
        .environment(\.chartPrototypeStyle, style)
    }

    private var chart: some View {
        SunburstChart(
            root: root, volume: volume, isProvisional: false,
            selectedItemID: selectedItemID, actions: actions
        )
        .padding(10)
    }

    private var branchList: some View {
        VStack(spacing: 14) {
            ForEach(Array(root.sortedChildren.prefix(7).enumerated()), id: \.element.id) { index, child in
                branchRow(child, index: index, compact: false)
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(theme.tertiaryText)
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
        }
    }

    private func branchRow(_ child: FileNode, index: Int, compact: Bool) -> some View {
        let color = branchColor(child, index: index)
        return Button {
            if child.isDirectory && !child.children.isEmpty { actions.inspect(child) }
            else { actions.select(child) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(child.name).lineLimit(1)
                    if !compact {
                        Spacer(minLength: 4)
                        Text(StorageFormatters.bytes(child.size)).monospacedDigit()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryText)
                if compact {
                    Text(StorageFormatters.bytes(child.size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                } else {
                    GeometryReader { proxy in
                        Capsule().fill(color.opacity(style == .contour ? 0.45 : 0.8))
                            .frame(width: max(2, proxy.size.width * child.percentage(of: root.size)))
                    }
                    .frame(height: style == .contour ? 2 : 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Inspect \(child.name), \(StorageFormatters.bytes(child.size))")
    }

    private func branchColor(_ child: FileNode, index: Int) -> Color {
        let hues = [0.49, 0.66, 0.09, 0.91, 0.34, 0.77, 0.02, 0.56]
        return style.color(
            hue: style == .classic ? SunburstLayout.hue(for: child.id) : hues[index % hues.count],
            depth: 0, isDark: colorScheme == .dark
        )
    }
}

@MainActor
enum ChartPrototypeExporter {
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in ChartPrototypeStyle.allCases {
            for scheme in [ColorScheme.dark, .light] {
                let content = ChartStylePrototypeStage(
                    style: style, root: ChartPrototypeData.disk, volume: ChartPrototypeData.volume
                )
                .frame(width: 1080, height: 730)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1.5
                guard let cgImage = renderer.cgImage else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let name = "\(style.rawValue)-\(scheme == .dark ? "dark" : "light").png"
                try png.write(to: directory.appendingPathComponent(name))
                print("Rendered \(name)")
            }
        }
    }
}
