import SwiftUI

// Hyperspace is the chosen theme. These are variations within that theme.
enum HyperspaceVariant: String, CaseIterable, Identifiable {
    case hologram, nebula, pulse

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var subtitle: String {
        switch self {
        case .hologram: "Fine glass-like edges. A light sweep follows the hovered sector."
        case .nebula: "Fuller luminous bands. A soft wave lights the hovered sector."
        case .pulse: "Crisp energy contours. A short tracer follows the hovered arc."
        }
    }

    var hoverHint: String {
        switch self {
        case .hologram: "HOVER / sector sweep"
        case .nebula: "HOVER / soft light wave"
        case .pulse: "HOVER / curved edge tracer"
        }
    }

    var starCount: Int {
        switch self {
        case .hologram: 180
        case .nebula: 240
        case .pulse: 100
        }
    }

    var glowRadius: CGFloat {
        switch self {
        case .hologram: 3
        case .nebula: 6
        case .pulse: 2
        }
    }

    static let branchHues = [0.53, 0.69, 0.10, 0.90, 0.38, 0.77, 0.02, 0.56]

    func shifted(by offset: Int) -> Self {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return Self.allCases[(index + offset + Self.allCases.count) % Self.allCases.count]
    }

    func hue(for segment: SunburstSegment, branches: [SunburstSegment]) -> Double {
        let midpoint = (segment.startAngle + segment.endAngle) / 2
        let index = branches.firstIndex {
            midpoint >= $0.startAngle && midpoint <= $0.endAngle
        } ?? 0
        return Self.branchHues[index % Self.branchHues.count]
    }

    func color(hue: Double, depth: Int, isDark: Bool) -> Color {
        Color(hue: hue, saturation: isDark ? 0.72 - Double(depth) * 0.035 : 0.77,
              brightness: isDark ? 0.78 + Double(depth) * 0.025 : 0.60 + Double(depth) * 0.018)
    }

    func accent(isDark: Bool) -> Color {
        color(hue: Self.branchHues[0], depth: 0, isDark: isDark)
    }

    func background(isDark: Bool) -> Color {
        isDark ? Color(red: 0.016, green: 0.035, blue: 0.075) : SpaceTheme(colorScheme: .light).surface
    }
}

private struct HyperspaceVariantKey: EnvironmentKey {
    // Normal application launches retain their existing presentation. Only the lab sets this.
    static let defaultValue: HyperspaceVariant? = nil
}

private struct HyperspaceMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var hyperspaceVariant: HyperspaceVariant? {
        get { self[HyperspaceVariantKey.self] }
        set { self[HyperspaceVariantKey.self] = newValue }
    }

    var hyperspaceMotionEnabled: Bool {
        get { self[HyperspaceMotionKey.self] }
        set { self[HyperspaceMotionKey.self] = newValue }
    }
}

enum HyperspaceRenderer {
    static func draw(
        _ segment: SunburstSegment, variant: HyperspaceVariant,
        branches: [SunburstSegment], context: inout GraphicsContext,
        center: CGPoint, radius: CGFloat, ringWidth: CGFloat, isDark: Bool
    ) {
        let color = variant.color(hue: variant.hue(for: segment, branches: branches),
                                  depth: segment.depth, isDark: isDark)
        let gap = min(0.006, segment.angularSpan * 0.14)
        let start = segment.startAngle - .pi / 2 + gap
        let end = segment.endAngle - .pi / 2 - gap
        let halfWidth = max(2, ringWidth - 2.5) / 2
        let inner = radius - halfWidth
        let outer = radius + halfWidth
        let tile = sector(center: center, inner: inner, outer: outer, start: start, end: end)
        let opacities: [Double]
        switch variant {
        case .hologram: opacities = [0.10, isDark ? 0.28 : 0.19]
        case .nebula: opacities = [isDark ? 0.20 : 0.17, isDark ? 0.65 : 0.46]
        case .pulse: opacities = [0.035, isDark ? 0.15 : 0.11]
        }
        context.fill(tile, with: .radialGradient(
            Gradient(colors: opacities.map { color.opacity($0) }),
            center: center, startRadius: inner, endRadius: outer
        ))
        context.stroke(tile, with: .color(color.opacity(variant == .pulse ? 0.35 : 0.56)), lineWidth: 0.6)
        var light = context
        light.addFilter(.shadow(color: color.opacity(isDark ? 0.8 : 0.16), radius: variant.glowRadius))
        light.stroke(arc(center: center, radius: outer - 0.9, start: start, end: end),
                     with: .color(color), lineWidth: variant == .pulse ? 1.8 : 1.2)
        if variant == .nebula {
            context.stroke(arc(center: center, radius: inner + 0.8, start: start, end: end),
                           with: .color(color.opacity(0.7)), lineWidth: 0.8)
        }
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
