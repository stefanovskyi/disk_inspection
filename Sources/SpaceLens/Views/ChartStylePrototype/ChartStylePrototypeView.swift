import AppKit
import SwiftUI

// Prototype only. Run `make chart-preview`; no filesystem scan or persisted settings.
struct ChartStylePrototypeView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var variant = HyperspaceVariant.hologram
    @State private var motionEnabled = true
    @State private var lightAppearance = false
    @State private var compactDataset = false
    @State private var path = [ChartPrototypeData.disk]
    @State private var selectedItem: FileNode?

    private var root: FileNode { path.last ?? ChartPrototypeData.disk }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Label("SpaceLens · Hyperspace lab", systemImage: "circle.hexagongrid")
                    .font(.headline)
                Spacer()
                Picker("Sample", selection: $compactDataset) {
                    Text("Disk · deep hierarchy").tag(false)
                    Text("Folder · shallow hierarchy").tag(true)
                }
                .labelsHidden()
                .frame(width: 220)
                Toggle("Motion", isOn: $motionEnabled)
                    .toggleStyle(.switch)
                    .disabled(systemReduceMotion)
                    .help("Hover animations respect the macOS Reduce Motion setting")
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

            HyperspaceStage(
                variant: variant, root: root,
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
                Button { variant = variant.shifted(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous variant")
                .keyboardShortcut(.leftArrow, modifiers: [])
                Picker("Hyperspace variant", selection: $variant) {
                    ForEach(HyperspaceVariant.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
                Button { variant = variant.shifted(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next variant")
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
        .environment(\.hyperspaceMotionEnabled, motionEnabled && !systemReduceMotion)
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
