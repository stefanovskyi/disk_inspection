import SwiftUI

/// How a clickable element answers the pointer. Every style draws outside layout, so hovering never shifts content.
enum HoverFeedbackStyle {
    /// Narrow selectable rows in the sidebar and ranked lists: a soft wash, an accent outline, and a slight lift.
    case row(cornerRadius: CGFloat)
    /// Wide rows inside detail panels: the wash and outline without a lift, which would be too large at full width.
    /// `outset` widens the highlight for rows whose content runs edge to edge.
    case surface(cornerRadius: CGFloat, outset: CGFloat = 0)
    /// Buttons and menus that draw their own chrome: a slight lift only.
    case control
}

private struct HoverFeedbackModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    let style: HoverFeedbackStyle
    let isInteractive: Bool

    func body(content: Content) -> some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let isActive = isHovering && isEnabled && isInteractive

        content
            .overlay {
                if let highlight {
                    RoundedRectangle(cornerRadius: highlight.cornerRadius, style: .continuous)
                        .fill(theme.primaryText.opacity(colorScheme == .dark ? 0.045 : 0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: highlight.cornerRadius, style: .continuous)
                                .stroke(theme.accent.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.horizontal, -highlight.outset)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .scaleEffect(isActive && !reduceMotion ? liftScale : 1)
            .animation(.easeOut(duration: 0.16), value: isActive)
            .onHover { isHovering = $0 }
    }

    private var highlight: (cornerRadius: CGFloat, outset: CGFloat)? {
        switch style {
        case let .row(cornerRadius): (cornerRadius, 0)
        case let .surface(cornerRadius, outset): (cornerRadius, outset)
        case .control: nil
        }
    }

    private var liftScale: CGFloat {
        switch style {
        case .row: 1.015
        case .surface: 1
        case .control: 1.03
        }
    }
}

extension View {
    /// Apply before `disabled(_:)` so a disabled control stays still under the pointer.
    /// Pass `isInteractive: false` for rows that have nothing to do on click.
    func hoverFeedback(_ style: HoverFeedbackStyle, isInteractive: Bool = true) -> some View {
        modifier(HoverFeedbackModifier(style: style, isInteractive: isInteractive))
    }
}
