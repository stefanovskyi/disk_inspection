import SwiftUI

/// Stands in for an analysis page until its first report exists. Progress itself
/// lives in the sidebar panel so every scan reports in one place.
struct AnalysisInProgressView<Notice: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @ViewBuilder let notice: () -> Notice

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(title)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.primaryText)

            Text("Results appear here when it finishes. You can keep using SpaceLens; progress is shown in the sidebar.")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            notice()
                .padding(.top, 8)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
