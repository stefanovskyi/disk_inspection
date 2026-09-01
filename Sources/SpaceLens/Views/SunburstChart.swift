import SwiftUI

struct ChartPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    let node: FileNode

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Storage map")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Each ring is one level deeper")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                Label("Click to inspect", systemImage: "cursorarrow.click.2")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            SunburstChart(root: node)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 15) {
                Label("Hover for details", systemImage: "cursorarrow.motionlines")
                Label("Right-click for actions", systemImage: "menubar.rectangle")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .spacePanel()
    }
}

struct SunburstChart: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverLocation: CGPoint?

    let root: FileNode

    private var segments: [SunburstSegment] {
        SunburstLayout.segments(for: root)
    }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        GeometryReader { proxy in
            let metrics = ChartMetrics(size: proxy.size, segments: segments)

            ZStack {
                Canvas(rendersAsynchronously: true) { context, _ in
                    drawBackgroundRings(context: &context, metrics: metrics, theme: theme)
                    drawSegments(context: &context, metrics: metrics)
                }

                centerSummary(metrics: metrics, theme: theme)

                if let hovered = model.hoveredNode, let hoverLocation {
                    ChartHoverCard(node: hovered, rootSize: root.size)
                        .frame(width: 224)
                        .position(tooltipPosition(for: hoverLocation, in: proxy.size))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverLocation = point
                    model.hoveredNode = segment(at: point, metrics: metrics)?.node
                case .ended:
                    hoverLocation = nil
                    model.hoveredNode = nil
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let node = segment(at: value.location, metrics: metrics)?.node else { return }
                        model.navigate(into: node)
                    }
            )
            .contextMenu {
                if let node = model.hoveredNode {
                    if node.isAggregate {
                        Button("Show Containing Folder in Finder") { model.showInFinder(node) }
                        Button("Open Containing Folder in Terminal") { model.openInTerminal(node) }
                    } else if node.isDirectory, !node.children.isEmpty {
                        Button("Inspect “\(node.name)”") { model.navigate(into: node) }
                        Divider()
                        Button("Show in Finder") { model.showInFinder(node) }
                        Button("Open in Terminal") { model.openInTerminal(node) }
                    } else {
                        Button("Show in Finder") { model.showInFinder(node) }
                        Button("Open in Terminal") { model.openInTerminal(node) }
                    }
                } else {
                    Button("Show “\(root.name)” in Finder") { model.showInFinder(root) }
                    Button("Open in Terminal") { model.openInTerminal(root) }
                }
            }
            .animation(.easeOut(duration: 0.14), value: model.hoveredNode?.id)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage sunburst for \(root.name), totaling \(StorageFormatters.bytes(root.size))")
        .accessibilityHint("Use the item list to inspect the same hierarchy with VoiceOver")
    }

    private func drawBackgroundRings(
        context: inout GraphicsContext,
        metrics: ChartMetrics,
        theme: SpaceTheme
    ) {
        guard metrics.ringCount > 0 else { return }
        for depth in 0..<metrics.ringCount {
            let radius = metrics.radius(forDepth: depth)
            let rect = CGRect(
                x: metrics.center.x - radius,
                y: metrics.center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(theme.border.opacity(0.65)),
                lineWidth: max(1, metrics.ringWidth - 3)
            )
        }
    }

    private func drawSegments(context: inout GraphicsContext, metrics: ChartMetrics) {
        for segment in segments {
            let isHovered = model.hoveredNode?.id == segment.node.id
            let angularGap = min(0.008, segment.angularSpan * 0.16)
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
                with: .color(isHovered ? color.opacity(1) : color.opacity(0.86)),
                style: StrokeStyle(
                    lineWidth: max(2, metrics.ringWidth - (isHovered ? 1 : 4)),
                    lineCap: .butt
                )
            )

            if isHovered {
                context.stroke(
                    arc,
                    with: .color(Color.white.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .butt)
                )
            }
        }
    }

    private func centerSummary(metrics: ChartMetrics, theme: SpaceTheme) -> some View {
        let displayNode = model.hoveredNode ?? root
        let size = max(metrics.innerRadius * 1.72, 84)

        return ZStack {
            Circle()
                .fill(theme.background)
            Circle()
                .stroke(theme.border, lineWidth: 1)

            VStack(spacing: 3) {
                Text(StorageFormatters.bytes(displayNode.size))
                    .font(.system(size: min(24, metrics.innerRadius * 0.26), weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(displayNode.name)
                    .font(.system(size: 11, weight: .medium))
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

    private func segment(at point: CGPoint, metrics: ChartMetrics) -> SunburstSegment? {
        let dx = point.x - metrics.center.x
        let dy = point.y - metrics.center.y
        let distance = hypot(dx, dy)
        guard distance >= metrics.innerRadius,
              distance <= metrics.outerRadius + 2,
              metrics.ringWidth > 0 else { return nil }

        let depth = Int((distance - metrics.innerRadius) / metrics.ringWidth)
        var angle = atan2(dy, dx) + (.pi / 2)
        if angle < 0 { angle += .pi * 2 }

        return segments.first {
            $0.depth == depth && angle >= $0.startAngle && angle <= $0.endAngle
        }
    }

    private func tooltipPosition(for point: CGPoint, in size: CGSize) -> CGPoint {
        let cardWidth: CGFloat = 224
        let cardHeight: CGFloat = 91
        let proposedX = point.x + (point.x < size.width * 0.62 ? 126 : -126)
        let proposedY = point.y + (point.y < size.height * 0.26 ? 55 : -55)
        return CGPoint(
            x: min(max(cardWidth / 2 + 8, proposedX), size.width - cardWidth / 2 - 8),
            y: min(max(cardHeight / 2 + 8, proposedY), size.height - cardHeight / 2 - 8)
        )
    }
}

private struct ChartMetrics {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let ringWidth: CGFloat
    let ringCount: Int

    init(size: CGSize, segments: [SunburstSegment]) {
        let diameter = min(size.width, size.height)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        innerRadius = max(54, diameter * 0.145)
        outerRadius = max(innerRadius + 24, diameter * 0.465)
        ringCount = max(1, (segments.map(\.depth).max() ?? 0) + 1)
        ringWidth = max(1, (outerRadius - innerRadius) / CGFloat(ringCount))
    }

    func radius(forDepth depth: Int) -> CGFloat {
        innerRadius + ringWidth * (CGFloat(depth) + 0.5)
    }
}

private struct ChartHoverCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let node: FileNode
    let rootSize: Int64

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(theme.accent)
                Text(node.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack {
                Text(StorageFormatters.bytes(node.size))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text(StorageFormatters.percent(node.percentage(of: rootSize)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }

            Text(node.isAggregate ? "\(node.itemCount.formatted()) grouped items" : node.url.path)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(theme.primaryText)
        .padding(11)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
    }
}
