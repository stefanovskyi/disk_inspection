import AppKit
import SwiftUI

// Throwaway design exploration on prototype/storage-map-styles.
// Question: which surface treatment makes the existing sunburst easier and more enjoyable to explore?
enum ChartPrototypeStyle: String, CaseIterable, Identifiable {
    case classic, aurora, prism, contour

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var subtitle: String {
        switch self {
        case .classic: "The current SpaceLens chart, for comparison."
        case .aurora: "Luminous bands. Soft light gives the hierarchy depth."
        case .prism: "Sculpted tiles. Crisp edges make every folder feel tangible."
        case .contour: "Quiet interiors. Fine contours trace the shape of your storage."
        }
    }

    var tradeoff: String {
        switch self {
        case .classic: "Simple solid fills and the current path-based colors."
        case .aurora: "The most expressive option. Subtle bloom softens very small boundaries."
        case .prism: "The clearest separation between tiles. Strong lighting adds visual density."
        case .contour: "The calmest option. Outlines emphasize structure more than filled area."
        }
    }

    func shifted(by offset: Int) -> Self {
        Self.allCases[(index + offset + Self.allCases.count) % Self.allCases.count]
    }

    /// Each top-level branch receives a distinct hue; all its descendants retain it.
    /// This is presentation only: segment angles, depths and targets remain untouched.
    func hue(for segment: SunburstSegment, branches: [SunburstSegment]) -> Double {
        guard self != .classic else { return segment.hue }
        let midpoint = (segment.startAngle + segment.endAngle) / 2
        let index = branches.firstIndex {
            midpoint >= $0.startAngle && midpoint <= $0.endAngle
        } ?? 0
        let hues = [0.49, 0.66, 0.09, 0.91, 0.34, 0.77, 0.02, 0.56]
        return hues[index % hues.count]
    }

    func color(hue: Double, depth: Int, isDark: Bool) -> Color {
        guard self != .classic else {
            return SpacePalette.color(hue: hue, depth: depth, isDark: isDark)
        }
        return Color(
            hue: hue,
            saturation: isDark ? 0.72 - Double(depth) * 0.035 : 0.77,
            brightness: isDark ? 0.78 + Double(depth) * 0.025 : 0.60 + Double(depth) * 0.018
        )
    }
}

private struct ChartPrototypeStyleKey: EnvironmentKey {
    static let defaultValue = ChartPrototypeStyle.classic
}

extension EnvironmentValues {
    var chartPrototypeStyle: ChartPrototypeStyle {
        get { self[ChartPrototypeStyleKey.self] }
        set { self[ChartPrototypeStyleKey.self] = newValue }
    }
}

enum ChartPrototypeRenderer {
    static func draw(
        _ segment: SunburstSegment,
        style: ChartPrototypeStyle,
        branches: [SunburstSegment],
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        ringWidth: CGFloat,
        isDark: Bool
    ) {
        let hue = style.hue(for: segment, branches: branches)
        let color = style.color(hue: hue, depth: segment.depth, isDark: isDark)
        let gap = min(0.006, segment.angularSpan * 0.14)
        let start = segment.startAngle - .pi / 2 + gap
        let end = segment.endAngle - .pi / 2 - gap
        let width = max(2, ringWidth - 2.5)
        let inner = radius - width / 2
        let outer = radius + width / 2
        let tile = wedge(center: center, inner: inner, outer: outer, start: start, end: end)

        switch style {
        case .classic:
            break // The original renderer handles this case without modification.
        case .aurora:
            var glow = context
            if isDark {
                glow.addFilter(.shadow(color: color.opacity(0.24), radius: 4))
            }
            glow.fill(tile, with: .radialGradient(
                Gradient(stops: [
                    .init(color: color.opacity(isDark ? 0.62 : 0.80), location: 0),
                    .init(color: color, location: 0.50),
                    .init(color: color.mix(with: .white, by: isDark ? 0.27 : 0.12), location: 0.92),
                    .init(color: color.opacity(0.76), location: 1)
                ]),
                center: center, startRadius: inner, endRadius: outer
            ))
            context.stroke(
                arc(center: center, radius: outer - 0.8, start: start, end: end),
                with: .color(color.mix(with: .white, by: 0.45).opacity(isDark ? 0.65 : 0.35)),
                lineWidth: 0.8
            )
        case .prism:
            context.fill(tile, with: .linearGradient(
                Gradient(colors: [
                    color.mix(with: .white, by: isDark ? 0.35 : 0.24),
                    color,
                    color.mix(with: .black, by: 0.33)
                ]),
                startPoint: CGPoint(x: center.x - outer, y: center.y - outer),
                endPoint: CGPoint(x: center.x + outer, y: center.y + outer)
            ))
            // A raised lip stays entirely inside the original segment geometry.
            context.stroke(tile, with: .color(color.mix(with: .white, by: 0.6).opacity(0.42)), lineWidth: 0.7)
            context.stroke(
                arc(center: center, radius: inner + 1.6, start: start, end: end),
                with: .color(.white.opacity(isDark ? 0.32 : 0.48)), lineWidth: 1.2
            )
            context.stroke(
                arc(center: center, radius: outer - 1, start: start, end: end),
                with: .color(.black.opacity(0.27)), lineWidth: 1.3
            )
        case .contour:
            context.fill(tile, with: .color(color.opacity(isDark ? 0.16 : 0.10)))
            context.stroke(tile, with: .color(color.opacity(isDark ? 0.68 : 0.62)), lineWidth: 0.8)
            context.stroke(
                arc(center: center, radius: outer - 1.4, start: start, end: end),
                with: .color(color), lineWidth: segment.depth == 0 ? 3 : 1.8
            )
        }
    }

    private static func arc(center: CGPoint, radius: CGFloat, start: Double, end: Double) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        return path
    }

    private static func wedge(center: CGPoint, inner: CGFloat, outer: CGFloat, start: Double, end: Double) -> Path {
        var path = arc(center: center, radius: outer, start: start, end: end)
        path.addArc(center: center, radius: inner, startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

private extension Color {
    // Color.mix is macOS 15+. Keep this prototype compatible with macOS 14.
    func mix(with other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.deviceRGB) ?? .white
        return Color(
            red: a.redComponent * (1 - amount) + b.redComponent * amount,
            green: a.greenComponent * (1 - amount) + b.greenComponent * amount,
            blue: a.blueComponent * (1 - amount) + b.blueComponent * amount
        )
    }
}
