import SwiftUI

extension ChartPrototypeStyle {
    func spaceAccent(isDark: Bool) -> Color {
        color(hue: branchHues[0], depth: 0, isDark: isDark)
    }

    func spaceBackground(isDark: Bool) -> Color {
        if !isDark { return SpaceTheme(colorScheme: .light).surface }
        return self == .bridge
            ? Color(red: 0.043, green: 0.047, blue: 0.078)
            : Color(red: 0.016, green: 0.035, blue: 0.075)
    }
}

/// Static atmosphere: no perpetual redraw, twinkling, or simulated scan progress.
struct SpaceChartAtmosphere: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: ChartPrototypeStyle
    let center: CGPoint
    let outerRadius: CGFloat

    var body: some View {
        let dark = colorScheme == .dark
        let accent = style.spaceAccent(isDark: dark)
        Canvas { context, size in
            for index in 0..<(style == .bridge ? 70 : 180) {
                let x = CGFloat((index * 137 + 31) % 997) / 997 * size.width
                let y = CGFloat((index * 293 + 79) % 991) / 991 * size.height
                let radius: CGFloat = index % 13 == 0 ? 1 : 0.45
                let opacity = dark ? (index % 7 == 0 ? 0.6 : 0.23) : 0.22
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color((index % 5 == 0 ? accent : SpaceTheme(colorScheme: colorScheme).secondaryText).opacity(opacity)))
            }

            let radius = outerRadius + 7
            let orbit = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: orbit), with: .color(accent.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 0.6, dash: [2, 7]))
            for index in 0..<120 {
                let angle = Double(index) / 120 * .pi * 2
                let major = index % 10 == 0
                var tick = Path()
                tick.move(to: point(center, outerRadius + 9, angle))
                tick.addLine(to: point(center, outerRadius + (major ? 15 : 11), angle))
                context.stroke(tick, with: .color(accent.opacity(major ? 0.7 : 0.22)), lineWidth: major ? 1.2 : 0.6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One bounded hover event. Its timeline stops after 1.2 seconds and when removed.
struct SpaceChartHoverEffect: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.chartPrototypeMotionEnabled) private var motionEnabled
    @State private var started = Date()
    @State private var isAnimating = true

    let style: ChartPrototypeStyle
    let segment: SunburstSegment
    let hue: Double
    let center: CGPoint
    let radius: CGFloat
    let hubRadius: CGFloat
    let ringWidth: CGFloat

    private var reduceMotion: Bool { systemReduceMotion || !motionEnabled }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isAnimating)) { timeline in
            let elapsed = reduceMotion ? 1.2 : min(1.2, max(0, timeline.date.timeIntervalSince(started)))
            Canvas { context, _ in
                draw(context: &context, elapsed: elapsed)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: segment.id) {
            started = Date()
            isAnimating = true
            guard !reduceMotion else { isAnimating = false; return }
            do { try await Task.sleep(for: .milliseconds(1200)) }
            catch { return }
            isAnimating = false
        }
    }

    private func draw(context: inout GraphicsContext, elapsed: Double) {
        let dark = colorScheme == .dark
        let color = style.color(hue: hue, depth: segment.depth, isDark: dark)
        let gap = min(0.006, segment.angularSpan * 0.14)
        let start = segment.startAngle - .pi / 2 + gap
        let end = segment.endAngle - .pi / 2 - gap
        let halfWidth = max(2, ringWidth - 2.5) / 2
        var tile = Path()
        tile.addArc(center: center, radius: radius + halfWidth, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        tile.addArc(center: center, radius: radius - halfWidth, startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
        tile.closeSubpath()
        let midpoint = (segment.startAngle + segment.endAngle) / 2
        let anchor = point(center, radius, midpoint)
        var glow = context
        glow.addFilter(.shadow(color: color.opacity(dark ? 0.9 : 0.25), radius: 6))
        glow.fill(tile, with: .color(color.opacity(0.20)))
        glow.stroke(tile, with: .color(dark ? .white.opacity(0.95) : color), lineWidth: 1.5)

        if elapsed < 1.1 && !reduceMotion {
            if style == .lasers {
                // Twin pulses travel only through the target's true ancestor sector.
                let travel = min(1, elapsed / 0.45)
                let head = hubRadius + (radius - hubRadius) * travel
                for offset in [-0.012, 0.012] {
                    var beam = Path()
                    beam.move(to: point(center, max(hubRadius, head - 35), midpoint + offset))
                    beam.addLine(to: point(center, head, midpoint + offset))
                    glow.stroke(beam, with: .color(color), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                    context.stroke(beam, with: .color(.white.opacity(0.9)), lineWidth: 0.7)
                }
                if elapsed > 0.40 {
                    let phase = min(1, (elapsed - 0.40) / 0.7)
                    let r = 3 + phase * 22
                    glow.stroke(Path(ellipseIn: CGRect(x: anchor.x - r, y: anchor.y - r, width: r * 2, height: r * 2)),
                                with: .color(color.opacity(1 - phase)), lineWidth: 1.3)
                }
            } else {
                var sweep = context
                sweep.clip(to: tile)
                let angle = segment.startAngle + segment.angularSpan * min(1, elapsed / 0.9)
                var beam = Path()
                beam.move(to: point(center, radius - halfWidth - 2, angle))
                beam.addLine(to: point(center, radius + halfWidth + 2, angle))
                sweep.addFilter(.shadow(color: color, radius: 7))
                sweep.stroke(beam, with: .color(dark ? .white : color), lineWidth: style == .bridge ? 4 : 2)
            }
        }

        let settle = reduceMotion ? 1 : min(1, elapsed / 0.35)
        let extent = 12 + (1 - settle) * 20
        var brackets = Path()
        for x in [-1.0, 1.0] {
            for y in [-1.0, 1.0] {
                let corner = CGPoint(x: anchor.x + x * extent, y: anchor.y + y * extent)
                brackets.move(to: CGPoint(x: corner.x - x * 5, y: corner.y))
                brackets.addLine(to: corner)
                brackets.addLine(to: CGPoint(x: corner.x, y: corner.y - y * 5))
            }
        }
        glow.stroke(brackets, with: .color(color), lineWidth: 1.2)
    }
}

private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
    CGPoint(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
}
