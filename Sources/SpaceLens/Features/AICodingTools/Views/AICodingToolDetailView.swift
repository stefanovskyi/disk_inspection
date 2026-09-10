import SwiftUI
struct AICodingToolDetail: View {
    @Environment(\.colorScheme) private var colorScheme
    let tool: AICodingToolReport
    let totalSize: Int64
    let actions: AICodingToolsViewActions
    @State private var expandedNodeIDs: Set<String> = []

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 46, height: 46)
                        .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tool.displayName)
                            .font(.title2.weight(.bold))
                        Text(detailSubtitle)
                            .font(.callout)
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(StorageFormatters.bytes(tool.size))
                            .font(.title2.weight(.semibold).monospacedDigit())
                        if totalSize > 0 {
                            Text(StorageFormatters.percent(Double(tool.size) / Double(totalSize)))
                                .font(.caption)
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                }
                .foregroundStyle(theme.primaryText)
                .padding(16)
                .spacePanel()

                AICodingInstallationsSummary(
                    installations: tool.installations,
                    showInFinder: actions.showInFinder
                )

                if tool.size == 0 {
                    noStorage(theme: theme)
                }

                if !tool.categories.isEmpty {
                    AICodingCompositionSummary(categories: tool.categories)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Locations")
                            .font(.headline)
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        Text("Folders and files · Largest first")
                            .font(.caption)
                            .foregroundStyle(theme.tertiaryText)
                    }

                    ForEach(tool.locations) { location in
                        AICodingLocationOutline(
                            location: location,
                            expandedNodeIDs: $expandedNodeIDs,
                            actions: actions
                        )
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var detailSubtitle: String {
        let installationText: String
        if tool.installations.isEmpty {
            installationText = "No recognized installation"
        } else {
            installationText = "\(tool.installations.count) "
                + (tool.installations.count == 1 ? "installation" : "installations")
        }
        if tool.itemCount == 0 {
            return installationText + " · No measurable storage"
        }
        if let date = tool.latestModificationDate {
            return installationText + " · \(tool.itemCount.formatted()) items · Latest storage change "
                + date.formatted(date: .abbreviated, time: .shortened)
        }
        return installationText + " · \(tool.itemCount.formatted()) items"
    }

    private func noStorage(theme: SpaceTheme) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(theme.tertiaryText)
                .accessibilityHidden(true)
            Text("No storage found")
                .font(.headline)
                .foregroundStyle(theme.primaryText)
            Text(
                tool.hasRecognizedInstallation
                    ? "An installation was found, but its known data locations are absent or empty."
                    : "Known data locations are absent or empty. This does not prove the tool was never installed."
            )
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .spacePanel()
    }

}

struct AICodingCompositionSummary: View {
    @Environment(\.colorScheme) private var colorScheme
    let categories: [AICodingCategoryBreakdown]

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 10) {
            Text("Storage composition")
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(categories) { category in
                    HStack(spacing: 8) {
                        Image(systemName: category.category.systemImage)
                            .foregroundStyle(categoryColor(category.category, colorScheme: colorScheme))
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(category.category.displayName)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(StorageFormatters.bytes(category.size))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(theme.primaryText)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(theme.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .spacePanel()
    }
}
