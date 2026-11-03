import SwiftUI

/// Static decoration. The data's missing descendants remain transparent.
struct HoloPulseAtmosphere: View {
    @Environment(\.colorScheme) private var colorScheme
    let center: CGPoint
    let outerRadius: CGFloat

    var body: some View {
        let dark = colorScheme == .dark
        let accent = HoloPulseStyle.accent(isDark: dark)
        Canvas { context, size in
            for index in 0..<180 {
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

/// A 1.2-second hover event, confined to the actual annular sector.
struct HoloPulseHoverEffect: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.chartMotionEnabled) private var motionEnabled
    @State private var started = Date()
    @State private var isAnimating = true

    let segment: SunburstSegment
    let hue: Double
    let center: CGPoint
    let radius: CGFloat
    let ringWidth: CGFloat

    private var reduceMotion: Bool { systemReduceMotion || !motionEnabled }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isAnimating)) { timeline in
            let elapsed = reduceMotion ? 1.2 : min(1.2, max(0, timeline.date.timeIntervalSince(started)))
            Canvas { context, _ in draw(context: &context, elapsed: elapsed) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: "\(segment.id):\(reduceMotion)") {
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
        let color = HoloPulseStyle.color(hue: hue, depth: segment.depth, isDark: dark)
        let gap = min(0.006, segment.angularSpan * 0.14)
        let start = segment.startAngle - .pi / 2 + gap
        let end = segment.endAngle - .pi / 2 - gap
        let halfWidth = max(2, ringWidth - 2.5) / 2
        let inner = radius - halfWidth
        let outer = radius + halfWidth
        let tile = HoloPulseRenderer.sector(center: center, inner: inner, outer: outer, start: start, end: end)
        var glow = context
        glow.addFilter(.shadow(color: color.opacity(dark ? 0.8 : 0.2), radius: 4))
        glow.fill(tile, with: .color(color.opacity(0.15)))
        glow.stroke(tile, with: .color(dark ? HoloPulseStyle.iceLight.opacity(0.75) : color), lineWidth: 1.1)

        guard elapsed < 1, !reduceMotion else { return }
        let phase = min(1, elapsed)
        var tracer = glow
        tracer.clip(to: tile)
        let head = start + (end - start) * (1 - pow(1 - phase, 2))
        let length = min(0.18, (end - start) * 0.25)
        for index in 0..<4 {
            let tail = max(start, head - length * Double(4 - index) / 4)
            tracer.stroke(HoloPulseRenderer.arc(center: center, radius: outer - 1.3,
                                               start: tail, end: head),
                          with: .color((dark ? HoloPulseStyle.iceLight : color).opacity(Double(index + 1) * 0.22)),
                          style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }
}

private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
    CGPoint(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
}
