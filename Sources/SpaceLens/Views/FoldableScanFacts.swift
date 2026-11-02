import SwiftUI

/// Covers existing results with the facts page while they refresh. Folding reveals
/// the results under a slim status bar. The results stay alive underneath, so
/// folding never loses a selection or redraws a chart.
struct FoldableScanFacts<Content: View>: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("layout.scanFactsFolded") private var isFolded = false
    @State private var isRevealed = false

    let topic: ScanFactTopic
    /// The refresh to report on, or `nil` when the results are up to date.
    let source: ScanFactsSource?
    @ViewBuilder let content: () -> Content

    private struct RevealKey: Hashable {
        let isActive: Bool
        let startedAt: Date?
    }

    var body: some View {
        let startedAt = source.flatMap(model.startedAt(for:))
        let showsFacts = source != nil && (isRevealed || isDelayOver(startedAt))

        VStack(spacing: 0) {
            if let source, showsFacts, isFolded {
                ScanFactsFoldedBar(source: source) { setFolded(false) }
            }

            ZStack {
                content()
                    .opacity(showsFacts && !isFolded ? 0 : 1)
                    .allowsHitTesting(!showsFacts || isFolded)
                    .accessibilityHidden(showsFacts && !isFolded)

                if let source, showsFacts, !isFolded {
                    ScanFactsView(topic: topic, source: source, onFold: { setFolded(true) })
                }
            }
        }
        .task(id: RevealKey(isActive: source != nil, startedAt: startedAt)) {
            await updateReveal(startedAt: startedAt)
        }
    }

    private func isDelayOver(_ startedAt: Date?) -> Bool {
        ScanFact.revealDelay(startedAt: startedAt, now: Date()) == 0
    }

    private func updateReveal(startedAt: Date?) async {
        guard source != nil else {
            isRevealed = false
            return
        }
        // Once shown, facts stay until the refresh ends, even as queued work starts.
        guard !isRevealed else { return }
        let delay = ScanFact.revealDelay(startedAt: startedAt, now: Date())
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
        }
        isRevealed = true
    }

    private func setFolded(_ folded: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            isFolded = folded
        }
    }
}

private struct ScanFactsFoldedBar: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let source: ScanFactsSource
    let unfold: () -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let activity = model.activity(for: source)

        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            if let activity {
                Text("Updating \(activity.title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(activity.status)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(action: unfold) {
                Label("Show Facts", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Unfold the facts page")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }
}
