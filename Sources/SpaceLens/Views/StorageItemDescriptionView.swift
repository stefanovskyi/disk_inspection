import SwiftUI

/// Explains what the inspected item is and whether it is safe to delete.
/// Text longer than `foldedLineLimit` lines stays folded until clicked.
struct StorageItemDescriptionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var foldedHeight: CGFloat = 0
    let description: StorageItemDescription

    private static let foldedLineLimit = 3

    private var isFoldable: Bool { fullHeight > foldedHeight + 1 }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 5) {
            Label(description.safety.label, systemImage: description.safety.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(safetyColor(theme: theme))

            if isFoldable {
                Button {
                    isExpanded.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        descriptionText(theme: theme)
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            Text(isExpanded ? "Show less" : "Show more")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Fold the description" : "Show the full description")
                .accessibilityLabel(description.text)
                .accessibilityValue(isExpanded ? "Expanded" : "Folded")
                .accessibilityHint(isExpanded ? "Folds the description" : "Shows the full description")
            } else {
                descriptionText(theme: theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func descriptionText(theme: SpaceTheme) -> some View {
        styledText(lineLimit: isExpanded ? nil : Self.foldedLineLimit)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Both measured copies wrap at the visible width, so resizing the
                // panel re-evaluates whether the text needs folding.
                ZStack {
                    styledText(lineLimit: nil)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                    styledText(lineLimit: Self.foldedLineLimit)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { foldedHeight = $0 }
                }
                .hidden()
            }
    }

    private func styledText(lineLimit: Int?) -> some View {
        Text(description.text)
            .font(.caption)
            .lineSpacing(2)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func safetyColor(theme: SpaceTheme) -> Color {
        switch description.safety {
        case .safeToClear: return theme.accent
        case .reviewFirst: return theme.secondaryText
        case .keep: return theme.warning
        }
    }
}

extension FileNode {
    /// Aggregates are synthetic, so their path describes nothing real.
    var storageDescription: StorageItemDescription? {
        isAggregate ? nil : StorageItemDescription.resolve(url: url, isDirectory: isDirectory)
    }
}
