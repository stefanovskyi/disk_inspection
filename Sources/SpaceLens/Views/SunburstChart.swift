import SwiftUI

struct ChartPanel: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let node: FileNode
    let volume: VolumeInfo?
    let isProvisional: Bool
    @Binding var selectedItem: FileNode?
    let inspectSmallerItems: (SunburstSmallerItems) -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Storage map")
                        .font(.headline)
                        .foregroundStyle(theme.primaryText)
                    Text("Each ring is one level deeper")
                        .font(.caption)
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                Label("Click a folder to open", systemImage: "cursorarrow.click.2")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            SunburstChart(
                root: node,
                volume: volume,
                isProvisional: isProvisional,
                selectedItemID: selectedItem?.id,
                actions: SunburstChartActions(
                    select: { selectedItem = $0 },
                    inspect: {
                        selectedItem = nil
                        model.navigate(into: $0)
                    },
                    inspectSmallerItems: {
                        selectedItem = nil
                        inspectSmallerItems($0)
                    },
                    showInFinder: { model.showInFinder($0) },
                    openInTerminal: { model.openInTerminal($0) }
                )
            )
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 15) {
                Label("Hover for details", systemImage: "cursorarrow.motionlines")
                Label("Click to open folders", systemImage: "return")
                Label("Right-click for actions", systemImage: "menubar.rectangle")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .spacePanel()
    }
}

struct SunburstChart: View {
    @StateObject private var sceneCache = SunburstSceneCache()
    let root: FileNode
    let volume: VolumeInfo?
    let isProvisional: Bool
    let selectedItemID: String?
    private let capacity: StorageChartCapacity
    private let actions: SunburstChartActions

    init(
        root: FileNode,
        volume: VolumeInfo?,
        isProvisional: Bool,
        selectedItemID: String? = nil,
        actions: SunburstChartActions = .disabled
    ) {
        self.root = root
        self.volume = volume
        self.isProvisional = isProvisional
        self.selectedItemID = selectedItemID
        self.actions = actions
        let capacity = StorageChartCapacity(
            root: root,
            volume: volume,
            isProvisional: isProvisional
        )
        self.capacity = capacity
    }

    var body: some View {
        GeometryReader { proxy in
            let sizingMetrics = ChartMetrics(size: proxy.size, ringCount: 6)
            let scene = sceneCache.scene(
                root: root,
                angularExtent: capacity.chartedAngularExtent,
                interactionRadius: Double(sizingMetrics.radius(forDepth: 0)),
                size: proxy.size,
                isProvisional: isProvisional
            )
            let metrics = ChartMetrics(size: proxy.size, ringCount: scene.ringCount)

            ZStack {
                SunburstBaseLayer(scene: scene, capacity: capacity, metrics: metrics)
                SunburstInteractionLayer(
                    root: root,
                    scene: scene,
                    capacity: capacity,
                    metrics: metrics,
                    availableSize: proxy.size,
                    isProvisional: isProvisional,
                    selectedItemID: selectedItemID,
                    actions: actions
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Use the item list to inspect the same hierarchy with VoiceOver")
    }

    private var accessibilitySummary: String {
        var summary = isProvisional
            ? "Live storage sunburst for \(root.name), with \(StorageFormatters.bytes(root.size)) mapped so far"
            : "Storage sunburst for \(root.name), totaling \(StorageFormatters.bytes(capacity.usedSpace))"
        if capacity.freeSpace > 0 {
            summary += ", with \(StorageFormatters.bytes(capacity.freeSpace)) free"
        }
        return summary
    }
}

private final class SunburstSceneCache: ObservableObject {
    private struct Key: Equatable {
        struct Child: Equatable {
            let id: String
            let size: Int64
            let itemCount: Int
        }

        let rootID: String
        let rootSize: Int64
        let itemCount: Int
        let children: [Child]
        let angularExtent: Double
        let width: Int
        let height: Int
        let isProvisional: Bool
    }

    private var cachedKey: Key?
    private var cachedScene: SunburstScene?

    func scene(
        root: FileNode,
        angularExtent: Double,
        interactionRadius: Double,
        size: CGSize,
        isProvisional: Bool
    ) -> SunburstScene {
        let key = Key(
            rootID: root.id,
            rootSize: root.size,
            itemCount: root.itemCount,
            children: root.children.map {
                Key.Child(id: $0.id, size: $0.size, itemCount: $0.itemCount)
            },
            angularExtent: angularExtent,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            isProvisional: isProvisional
        )
        if key == cachedKey, let cachedScene {
            return cachedScene
        }

        let scene = SunburstScene(
            root: root,
            maxDepth: 6,
            angularExtent: angularExtent,
            interactionRadius: interactionRadius,
            policy: .interactive
        )
        cachedKey = key
        cachedScene = scene
        return scene
    }
}

struct SunburstChartActions {
    let select: (FileNode) -> Void
    let inspect: (FileNode) -> Void
    let inspectSmallerItems: (SunburstSmallerItems) -> Void
    let showInFinder: (FileNode) -> Void
    let openInTerminal: (FileNode) -> Void

    static let disabled = SunburstChartActions(
        select: { _ in },
        inspect: { _ in },
        inspectSmallerItems: { _ in },
        showInFinder: { _ in },
        openInTerminal: { _ in }
    )
}

private struct SunburstBaseLayer: View {
    @Environment(\.colorScheme) private var colorScheme

    let scene: SunburstScene
    let capacity: StorageChartCapacity
    let metrics: ChartMetrics

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        Canvas(rendersAsynchronously: true) { context, _ in
            drawCapacityOutline(context: &context, theme: theme)
            drawUnmappedUsedSpace(context: &context, theme: theme)
            drawSegments(context: &context)
        }
        .allowsHitTesting(false)
    }

    private func drawUnmappedUsedSpace(
        context: inout GraphicsContext,
        theme: SpaceTheme
    ) {
        guard capacity.isProvisional,
              capacity.usedAngularExtent - capacity.chartedAngularExtent > 0.004 else { return }

        var track = Path()
        track.addArc(
            center: metrics.center,
            radius: metrics.outerRadius - (metrics.ringWidth / 2),
            startAngle: .radians(capacity.chartedAngularExtent - (.pi / 2)),
            endAngle: .radians(capacity.usedAngularExtent - (.pi / 2)),
            clockwise: false
        )
        context.stroke(
            track,
            with: .color(theme.elevatedSurface.opacity(0.9)),
            style: StrokeStyle(lineWidth: max(3, metrics.ringWidth - 2.5), lineCap: .butt)
        )
    }

    private func drawCapacityOutline(
        context: inout GraphicsContext,
        theme: SpaceTheme
    ) {
        let rect = CGRect(
            x: metrics.center.x - metrics.outerRadius,
            y: metrics.center.y - metrics.outerRadius,
            width: metrics.outerRadius * 2,
            height: metrics.outerRadius * 2
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(theme.border.opacity(0.4)),
            lineWidth: 1
        )
    }

    private func drawSegments(context: inout GraphicsContext) {
        for segment in scene.segments {
            let angularGap = min(0.006, segment.angularSpan * 0.14)
            let radius = metrics.radius(forDepth: segment.depth)
            var arc = Path()
            arc.addArc(
                center: metrics.center,
                radius: radius,
                startAngle: .radians(segment.startAngle - (.pi / 2) + angularGap),
                endAngle: .radians(segment.endAngle - (.pi / 2) - angularGap),
                clockwise: false
            )

            let color = SpacePalette.color(
                hue: segment.hue,
                depth: segment.depth,
                isDark: colorScheme == .dark
            )
            context.stroke(
                arc,
                with: .color(color.opacity(0.86)),
                style: StrokeStyle(
                    lineWidth: max(2, metrics.ringWidth - 2.5),
                    lineCap: .butt
                )
            )
        }
    }
}

private struct SunburstInteractionLayer: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredSegmentIndex: Int?
    @State private var isHoveringFreeSpace = false

    let root: FileNode
    let scene: SunburstScene
    let capacity: StorageChartCapacity
    let metrics: ChartMetrics
    let availableSize: CGSize
    let isProvisional: Bool
    let selectedItemID: String?
    let actions: SunburstChartActions

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ZStack {
            if let selectedSegment {
                Canvas { context, _ in
                    drawSelection(segment: selectedSegment, context: &context)
                }
                .allowsHitTesting(false)
            }

            if let hoveredSegment {
                Canvas { context, _ in
                    drawHover(segment: hoveredSegment, context: &context)
                }
                .allowsHitTesting(false)
            }

            centerSummary(theme: theme)
            freeSpaceLabel(theme: theme)

            if let hoveredSegment {
                ChartHoverCard(segment: hoveredSegment, rootSize: root.size)
                    .frame(width: 224)
                    .position(tooltipPosition(for: hoveredSegment, in: availableSize))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: availableSize.width, height: availableSize.height)
        .contentShape(Rectangle())
        .onContinuousHover(perform: handleHover)
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard let index = segmentIndex(at: value.location) else { return }
                    performPrimaryAction(for: scene.segments[index])
                }
        )
        .contextMenu { contextMenu }
    }

    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            let nextSegmentIndex = segmentIndex(at: point)
            if nextSegmentIndex != hoveredSegmentIndex {
                hoveredSegmentIndex = nextSegmentIndex
            }
            let nextIsFreeSpace = nextSegmentIndex == nil && isFreeSpace(at: point)
            if nextIsFreeSpace != isHoveringFreeSpace {
                isHoveringFreeSpace = nextIsFreeSpace
            }
        case .ended:
            hoveredSegmentIndex = nil
            isHoveringFreeSpace = false
        }
    }

    private var hoveredSegment: SunburstSegment? {
        guard let index = hoveredSegmentIndex,
              scene.segments.indices.contains(index) else { return nil }
        return scene.segments[index]
    }

    private var selectedSegment: SunburstSegment? {
        guard let selectedItemID else { return nil }
        return scene.segments.first { segment in
            guard case .node(let node) = segment.target else { return false }
            return node.id == selectedItemID
        }
    }

    private func performPrimaryAction(for segment: SunburstSegment) {
        switch segment.target {
        case .node(let node):
            if node.isDirectory, !node.children.isEmpty {
                actions.inspect(node)
            } else {
                actions.select(node)
            }
        case .smallerItems(let group):
            actions.inspectSmallerItems(group)
        }
    }

    private func inspect(_ segment: SunburstSegment) {
        switch segment.target {
        case .node(let node):
            actions.inspect(node)
        case .smallerItems(let group):
            actions.inspectSmallerItems(group)
        }
    }

    private func drawHover(segment: SunburstSegment, context: inout GraphicsContext) {
        let angularGap = min(0.006, segment.angularSpan * 0.14)
        let radius = metrics.radius(forDepth: segment.depth)
        var arc = Path()
        arc.addArc(
            center: metrics.center,
            radius: radius,
            startAngle: .radians(segment.startAngle - (.pi / 2) + angularGap),
            endAngle: .radians(segment.endAngle - (.pi / 2) - angularGap),
            clockwise: false
        )
        let color = SpacePalette.color(
            hue: segment.hue,
            depth: segment.depth,
            isDark: colorScheme == .dark
        )
        context.stroke(
            arc,
            with: .color(color),
            style: StrokeStyle(lineWidth: max(2, metrics.ringWidth - 0.5), lineCap: .butt)
        )
        context.stroke(
            arc,
            with: .color(Color.white.opacity(0.75)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .butt)
        )
    }

    private func drawSelection(segment: SunburstSegment, context: inout GraphicsContext) {
        let angularGap = min(0.006, segment.angularSpan * 0.14)
        let radius = metrics.radius(forDepth: segment.depth)
        var arc = Path()
        arc.addArc(
            center: metrics.center,
            radius: radius,
            startAngle: .radians(segment.startAngle - (.pi / 2) + angularGap),
            endAngle: .radians(segment.endAngle - (.pi / 2) - angularGap),
            clockwise: false
        )
        context.stroke(
            arc,
            with: .color(Color.accentColor.opacity(0.95)),
            style: StrokeStyle(lineWidth: max(3, metrics.ringWidth + 1.5), lineCap: .butt)
        )
    }

    private func centerSummary(theme: SpaceTheme) -> some View {
        let focusedSegment = hoveredSegment ?? selectedSegment
        let displaySize = isHoveringFreeSpace
            ? capacity.freeSpace
            : (focusedSegment?.size ?? (isProvisional ? root.size : capacity.usedSpace))
        let displayName = isHoveringFreeSpace
            ? "Free space"
            : (focusedSegment?.name ?? (isProvisional ? "\(root.name) mapped" : root.name))
        let size = max(metrics.innerRadius * 1.72, 84)

        return ZStack {
            Circle()
                .fill(theme.background)
            Circle()
                .stroke(theme.border, lineWidth: 1)

            VStack(spacing: 3) {
                Text(StorageFormatters.bytes(displaySize))
                    .font(.system(size: min(24, metrics.innerRadius * 0.26), weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
            }
        }
        .frame(width: size, height: size)
        .position(metrics.center)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func freeSpaceLabel(theme: SpaceTheme) -> some View {
        if capacity.freeAngularSpan >= 0.22, capacity.freeSpace > 0 {
            let midpoint = capacity.usedAngularExtent + (capacity.freeAngularSpan / 2)
            let labelRadius = metrics.innerRadius + ((metrics.outerRadius - metrics.innerRadius) * 0.58)
            let position = CGPoint(
                x: metrics.center.x + sin(midpoint) * labelRadius,
                y: metrics.center.y - cos(midpoint) * labelRadius
            )

            VStack(spacing: 2) {
                Text("FREE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                Text(StorageFormatters.bytes(capacity.freeSpace))
                    .font(.caption.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
            }
            .foregroundStyle(isHoveringFreeSpace ? theme.primaryText : theme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.surface.opacity(isHoveringFreeSpace ? 0.9 : 0.62))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.border.opacity(0.75), lineWidth: 1)
            }
            .position(position)
            .allowsHitTesting(false)
        }
    }

    private func segmentIndex(at point: CGPoint) -> Int? {
        let dx = point.x - metrics.center.x
        let dy = point.y - metrics.center.y
        let distance = hypot(dx, dy)
        guard distance >= metrics.innerRadius,
              distance <= metrics.outerRadius + 2,
              metrics.ringWidth > 0 else { return nil }

        let depth = Int((distance - metrics.innerRadius) / metrics.ringWidth)
        var angle = atan2(dy, dx) + (.pi / 2)
        if angle < 0 { angle += .pi * 2 }
        return scene.segmentIndex(atDepth: depth, angle: angle)
    }

    private func isFreeSpace(at point: CGPoint) -> Bool {
        guard capacity.freeSpace > 0 else { return false }
        let dx = point.x - metrics.center.x
        let dy = point.y - metrics.center.y
        let distance = hypot(dx, dy)
        guard distance >= metrics.innerRadius, distance <= metrics.outerRadius + 2 else {
            return false
        }

        var angle = atan2(dy, dx) + (.pi / 2)
        if angle < 0 { angle += .pi * 2 }
        return angle > capacity.usedAngularExtent
    }

    private func tooltipPosition(for segment: SunburstSegment, in size: CGSize) -> CGPoint {
        let cardWidth: CGFloat = 224
        let cardHeight: CGFloat = 91
        let angle = segment.startAngle + (segment.angularSpan / 2)
        let radius = metrics.radius(forDepth: segment.depth)
        let anchor = CGPoint(
            x: metrics.center.x + sin(angle) * radius,
            y: metrics.center.y - cos(angle) * radius
        )
        let proposedX = anchor.x + (anchor.x < size.width * 0.62 ? 126 : -126)
        let proposedY = anchor.y + (anchor.y < size.height * 0.26 ? 55 : -55)
        return CGPoint(
            x: min(max(cardWidth / 2 + 8, proposedX), size.width - cardWidth / 2 - 8),
            y: min(max(cardHeight / 2 + 8, proposedY), size.height - cardHeight / 2 - 8)
        )
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let hoveredSegment {
            switch hoveredSegment.target {
            case .smallerItems(let group):
                Button("View Smaller Items") { actions.inspectSmallerItems(group) }
                Divider()
                Button("Show Containing Folder in Finder") { actions.showInFinder(group.parent) }
                Button("Open Containing Folder in Terminal") { actions.openInTerminal(group.parent) }
            case .node(let node):
                if node.isAggregate {
                    Button("Show Containing Folder in Finder") { actions.showInFinder(node) }
                    Button("Open Containing Folder in Terminal") { actions.openInTerminal(node) }
                } else if node.isDirectory, !node.children.isEmpty {
                    Button("Inspect “\(node.name)”") { actions.inspect(node) }
                    Divider()
                    Button("Show in Finder") { actions.showInFinder(node) }
                    Button("Open in Terminal") { actions.openInTerminal(node) }
                } else {
                    Button("Show in Finder") { actions.showInFinder(node) }
                    Button("Open in Terminal") { actions.openInTerminal(node) }
                }
            }
        } else {
            Button("Show “\(root.name)” in Finder") { actions.showInFinder(root) }
            Button("Open in Terminal") { actions.openInTerminal(root) }
        }
    }
}

private struct StorageChartCapacity {
    let usedSpace: Int64
    let freeSpace: Int64
    let totalSpace: Int64

    let mappedSpace: Int64
    let isProvisional: Bool

    init(root: FileNode, volume: VolumeInfo?, isProvisional: Bool) {
        self.isProvisional = isProvisional
        mappedSpace = max(root.size, 0)
        if let volume, volume.totalCapacity > 0 {
            totalSpace = volume.totalCapacity
            freeSpace = min(max(volume.availableCapacity, 0), volume.totalCapacity)
            usedSpace = max(volume.totalCapacity - freeSpace, 0)
        } else {
            usedSpace = max(root.size, 0)
            freeSpace = 0
            totalSpace = max(root.size, 0)
        }
    }

    var usedFraction: Double {
        guard totalSpace > 0 else { return 0 }
        return min(max(Double(usedSpace) / Double(totalSpace), 0), 1)
    }

    var usedAngularExtent: Double { usedFraction * .pi * 2 }
    var chartedAngularExtent: Double {
        guard isProvisional, totalSpace > 0, mappedSpace < totalSpace else {
            return usedAngularExtent
        }
        let mappedFraction = min(max(Double(mappedSpace) / Double(totalSpace), 0), usedFraction)
        return mappedFraction * .pi * 2
    }
    var freeAngularSpan: Double { (.pi * 2) - usedAngularExtent }
}

private struct ChartMetrics {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let ringWidth: CGFloat
    let ringCount: Int

    init(size: CGSize, ringCount: Int) {
        let diameter = min(size.width, size.height)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        innerRadius = max(54, diameter * 0.145)
        outerRadius = max(innerRadius + 24, diameter * 0.465)
        self.ringCount = max(1, ringCount)
        ringWidth = max(1, (outerRadius - innerRadius) / CGFloat(self.ringCount))
    }

    func radius(forDepth depth: Int) -> CGFloat {
        innerRadius + ringWidth * (CGFloat(depth) + 0.5)
    }
}

private struct ChartHoverCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let segment: SunburstSegment
    let rootSize: Int64

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: iconName)
                    .foregroundStyle(theme.accent)
                Text(segment.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack {
                Text(StorageFormatters.bytes(segment.size))
                    .font(.callout.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Spacer()
                Text(StorageFormatters.percent(percentage))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
            }

            Text(detail)
                .font(.caption2.monospaced())
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(theme.primaryText)
        .padding(11)
        .background(theme.surface.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
    }

    private var percentage: Double {
        guard rootSize > 0 else { return 0 }
        return min(max(Double(segment.size) / Double(rootSize), 0), 1)
    }

    private var iconName: String {
        switch segment.target {
        case .smallerItems:
            return "ellipsis.circle.fill"
        case .node(let node):
            if node.isAggregate { return "ellipsis.circle.fill" }
            return node.isDirectory ? "folder.fill" : "doc.fill"
        }
    }

    private var detail: String {
        switch segment.target {
        case .smallerItems(let group):
            return "\(group.itemCount.formatted()) grouped items in \(group.parent.name)"
        case .node(let node):
            return node.isAggregate ? "\(node.itemCount.formatted()) grouped items" : node.url.path
        }
    }
}
