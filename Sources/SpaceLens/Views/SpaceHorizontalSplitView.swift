import AppKit
import SwiftUI

struct SpaceHorizontalSplitView<Leading: View, Trailing: View>: View {
    @Binding private var trailingWidth: Double
    @State private var dragStartWidth: Double?

    private let minimumLeadingWidth: CGFloat
    private let minimumTrailingWidth: CGFloat
    private let maximumTrailingWidth: CGFloat
    private let spacing: CGFloat
    private let dividerAccessibilityLabel: String
    private let leading: Leading
    private let trailing: Trailing

    init(
        trailingWidth: Binding<Double>,
        minimumLeadingWidth: CGFloat = 500,
        minimumTrailingWidth: CGFloat = AppLayoutMetrics.minimumInspectorWidth,
        maximumTrailingWidth: CGFloat = AppLayoutMetrics.maximumInspectorWidth,
        spacing: CGFloat = 12,
        dividerAccessibilityLabel: String = "Resize details panel",
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        _trailingWidth = trailingWidth
        self.minimumLeadingWidth = minimumLeadingWidth
        self.minimumTrailingWidth = minimumTrailingWidth
        self.maximumTrailingWidth = maximumTrailingWidth
        self.spacing = spacing
        self.dividerAccessibilityLabel = dividerAccessibilityLabel
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedTrailingWidth = resolvedTrailingWidth(for: proxy.size.width)
            let leadingWidth = max(0, proxy.size.width - resolvedTrailingWidth - spacing)

            HStack(spacing: 0) {
                leading
                    .frame(width: leadingWidth)

                resizeGutter(
                    availableWidth: proxy.size.width,
                    resolvedTrailingWidth: resolvedTrailingWidth
                )

                trailing
                    .frame(width: resolvedTrailingWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func resizeGutter(
        availableWidth: CGFloat,
        resolvedTrailingWidth: CGFloat
    ) -> some View {
        Color.clear
            .frame(width: spacing)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let initialWidth = dragStartWidth ?? Double(resolvedTrailingWidth)
                        if dragStartWidth == nil {
                            dragStartWidth = initialWidth
                        }
                        trailingWidth = Double(
                            clampedTrailingWidth(
                                CGFloat(initialWidth) - value.translation.width,
                                availableWidth: availableWidth
                            )
                        )
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(dividerAccessibilityLabel)
            .accessibilityValue("\(Int(resolvedTrailingWidth.rounded())) points wide")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 20 : -20
                trailingWidth = Double(
                    clampedTrailingWidth(
                        resolvedTrailingWidth + delta,
                        availableWidth: availableWidth
                    )
                )
            }
    }

    private func resolvedTrailingWidth(for availableWidth: CGFloat) -> CGFloat {
        clampedTrailingWidth(CGFloat(trailingWidth), availableWidth: availableWidth)
    }

    private func clampedTrailingWidth(
        _ proposedWidth: CGFloat,
        availableWidth: CGFloat
    ) -> CGFloat {
        let availableForTrailing = max(
            minimumTrailingWidth,
            availableWidth - minimumLeadingWidth - spacing
        )
        return min(
            max(proposedWidth, minimumTrailingWidth),
            min(maximumTrailingWidth, availableForTrailing)
        )
    }
}
