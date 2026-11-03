import SwiftUI

/// The single chart style used by SpaceLens: translucent bands and a curved hover tracer.
enum HoloPulseStyle {
    static let iceLight = Color(red: 0.72, green: 0.91, blue: 1)
    static let branchHues = [0.53, 0.69, 0.10, 0.90, 0.38, 0.77, 0.02, 0.56]

    static func branchHue(at index: Int) -> Double {
        branchHues[max(0, index) % branchHues.count]
    }

    static func hue(for segment: SunburstSegment, branches: [SunburstSegment]) -> Double {
        let midpoint = (segment.startAngle + segment.endAngle) / 2
        let index = branches.firstIndex {
            midpoint >= $0.startAngle && midpoint <= $0.endAngle
        } ?? 0
        return branchHue(at: index)
    }

    static func color(hue: Double, depth: Int, isDark: Bool) -> Color {
        Color(hue: hue, saturation: isDark ? 0.72 - Double(depth) * 0.035 : 0.77,
              brightness: isDark ? 0.78 + Double(depth) * 0.025 : 0.44 + Double(depth) * 0.01)
    }

    static func accent(isDark: Bool) -> Color {
        isDark ? color(hue: branchHues[0], depth: 0, isDark: true)
            : SpaceTheme(colorScheme: .light).accent
    }
}

private struct ChartMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var chartMotionEnabled: Bool {
        get { self[ChartMotionKey.self] }
        set { self[ChartMotionKey.self] = newValue }
    }
}

struct HoloPulsePanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let dark = colorScheme == .dark
        let navy = Color(red: 0.016, green: 0.035, blue: 0.075)
        content
            .background(LinearGradient(
                colors: dark ? [navy, navy] : [theme.surface, theme.sidebar],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HoloPulseStyle.accent(isDark: dark).opacity(0.35), lineWidth: 1)
            }
    }
}

extension View {
    func holoPulsePanel() -> some View { modifier(HoloPulsePanelModifier()) }
}

enum HoloPulseRenderer {
    static func draw(
        _ segment: SunburstSegment,
        branches: [SunburstSegment], context: inout GraphicsContext,
        center: CGPoint, radius: CGFloat, ringWidth: CGFloat, isDark: Bool
    ) {
        let color = HoloPulseStyle.color(hue: HoloPulseStyle.hue(for: segment, branches: branches),
                                        depth: segment.depth, isDark: isDark)
        let gap = min(0.006, segment.angularSpan * 0.14)
        let start = segment.startAngle - .pi / 2 + gap
        let end = segment.endAngle - .pi / 2 - gap
        let halfWidth = max(2, ringWidth - 2.5) / 2
        let inner = radius - halfWidth
        let outer = radius + halfWidth
        let tile = sector(center: center, inner: inner, outer: outer, start: start, end: end)
        let opacities = [0.10, isDark ? 0.28 : 0.19]
        context.fill(tile, with: .radialGradient(
            Gradient(colors: opacities.map { color.opacity($0) }),
            center: center, startRadius: inner, endRadius: outer
        ))
        context.stroke(tile, with: .color(color.opacity(0.56)), lineWidth: 0.6)
        var light = context
        light.addFilter(.shadow(color: color.opacity(isDark ? 0.8 : 0.16), radius: 3))
        light.stroke(arc(center: center, radius: outer - 0.9, start: start, end: end),
                     with: .color(color), lineWidth: 1.2)
    }

    static func arc(center: CGPoint, radius: CGFloat, start: Double, end: Double) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        return path
    }

    static func sector(center: CGPoint, inner: CGFloat, outer: CGFloat, start: Double, end: Double) -> Path {
        var path = arc(center: center, radius: outer, start: start, end: end)
        path.addArc(center: center, radius: inner, startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}
