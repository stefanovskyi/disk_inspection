import SwiftUI

/// Keeps people company during a scan: live progress above a rotating fact about
/// the page's subject. `.page` fills the content area; `.panel` sits beside the live chart.
struct ScanFactsView<Notice: View>: View {
    enum Layout { case page, panel }

    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fact: ScanFact?
    @State private var isHovering = false
    @State private var dwell: CGFloat = 0
    @State private var isGlowShifted = false

    let topic: ScanFactTopic
    let source: ScanFactsSource
    var layout: Layout = .page
    /// Offers to fold the page away when there are results underneath.
    var onFold: (() -> Void)?
    @ViewBuilder let notice: () -> Notice

    private struct RotationKey: Hashable {
        let text: String?
        let isPaused: Bool
    }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ZStack {
            background(theme: theme)

            VStack(spacing: layout == .page ? 26 : 18) {
                ScanFactsProgress(source: source, isCompact: layout == .panel)
                    .frame(maxWidth: layout == .page ? 720 : .infinity)

                factCard(theme: theme)
                    .frame(maxWidth: layout == .page ? 720 : .infinity)

                notice()
            }
            .padding(layout == .page ? 34 : 16)
        }
        .overlay(alignment: .topTrailing) {
            if let onFold {
                Button(action: onFold) {
                    Label("Show Results", systemImage: "chevron.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Fold the facts page to see the current results")
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            if fact == nil { fact = model.scanFacts.next(for: topic) }
            isGlowShifted = !reduceMotion
        }
        .task(id: RotationKey(text: fact?.text, isPaused: isHovering)) {
            await rotate()
        }
    }

    private func background(theme: SpaceTheme) -> some View {
        ZStack {
            theme.background
            RadialGradient(
                colors: [theme.accent.opacity(0.20), .clear],
                center: isGlowShifted ? .topLeading : .top,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [
                    SpacePalette.color(hue: 0.78, depth: 1, isDark: colorScheme == .dark).opacity(0.14),
                    .clear
                ],
                center: isGlowShifted ? .bottomTrailing : .trailing,
                startRadius: 0,
                endRadius: 480
            )
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 14).repeatForever(autoreverses: true),
            value: isGlowShifted
        )
        .accessibilityHidden(true)
    }

    private func factCard(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: layout == .page ? 16 : 12) {
            HStack(spacing: 8) {
                Image(systemName: topic.systemImage)
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text("Did you know?")
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)
                Spacer(minLength: 8)
                Button {
                    showNextFact()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.secondaryText)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Next fact")
                .accessibilityLabel("Next fact")
            }
            .font(.caption.weight(.bold))

            if let fact {
                VStack(alignment: .leading, spacing: 10) {
                    Text(fact.text)
                        .font(
                            .system(
                                size: layout == .page ? 23 : 16,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .lineSpacing(layout == .page ? 4 : 2)
                        .foregroundStyle(theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    Text("Source: \(fact.source)")
                        .font(.caption)
                        .foregroundStyle(theme.tertiaryText)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: layout == .page ? 170 : 0,
                    alignment: .topLeading
                )
                .id(fact.text)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 10)),
                            removal: .opacity
                        )
                )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.elevatedSurface)
                    Capsule()
                        .fill(theme.accent.opacity(isHovering ? 0.35 : 0.8))
                        .frame(width: proxy.size.width * dwell)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .padding(layout == .page ? 24 : 15)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surface.opacity(0.92))
                .shadow(color: theme.shadow.opacity(0.22), radius: 20, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [theme.accent.opacity(0.55), theme.border.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .onHover { isHovering = $0 }
        .help(isHovering ? "Paused while the pointer is here" : "")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fact about \(topic.title)")
    }

    private func rotate() async {
        guard let fact else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { dwell = 0 }
        // Hovering pauses rotation so a fact is never pulled away mid-sentence.
        guard !isHovering else { return }

        let duration = fact.readingDuration
        if !reduceMotion {
            withAnimation(.linear(duration: duration)) { dwell = 1 }
        }
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        showNextFact()
    }

    private func showNextFact() {
        let next = model.scanFacts.next(for: topic)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            fact = next
        }
    }
}

extension ScanFactsView where Notice == EmptyView {
    init(
        topic: ScanFactTopic,
        source: ScanFactsSource,
        layout: Layout = .page,
        onFold: (() -> Void)? = nil
    ) {
        self.init(topic: topic, source: source, layout: layout, onFold: onFold) { EmptyView() }
    }
}

/// Reads scan progress in its own view so frequent updates never disturb the fact above it.
private struct ScanFactsProgress: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let source: ScanFactsSource
    let isCompact: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        if let activity = model.activity(for: source) {
            if isCompact {
                VStack(alignment: .leading, spacing: 12) {
                    summary(activity, ringSize: 58, theme: theme)
                    stats(activity, theme: theme)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText(activity))
            } else {
                VStack(spacing: 16) {
                    summary(activity, ringSize: 84, theme: theme)
                    stats(activity, theme: theme)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText(activity))
            }
        }
    }

    private func summary(_ activity: ScanActivity, ringSize: CGFloat, theme: SpaceTheme) -> some View {
        HStack(spacing: isCompact ? 12 : 18) {
            ring(activity, size: ringSize, theme: theme)

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(isCompact ? .headline : .title2.weight(.bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(activity.status)
                    .font(isCompact ? .caption.weight(.medium) : .callout.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                if let path = activity.currentPath ?? activity.location, !path.isEmpty, !activity.isQueued {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if !isCompact { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func ring(_ activity: ScanActivity, size: CGFloat, theme: SpaceTheme) -> some View {
        ZStack {
            Circle()
                .stroke(theme.elevatedSurface, lineWidth: size * 0.09)
            if let fraction = activity.fraction, !activity.isQueued {
                Circle()
                    .trim(from: 0, to: max(fraction, 0.01))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.primaryText)
            } else if activity.isQueued {
                Image(systemName: "hourglass")
                    .font(.system(size: size * 0.3, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            } else {
                ProgressView()
                    .controlSize(isCompact ? .small : .regular)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func stats(_ activity: ScanActivity, theme: SpaceTheme) -> some View {
        HStack(spacing: isCompact ? 8 : 12) {
            if let mappedBytes = activity.mappedBytes {
                stat(
                    StorageFormatters.bytes(mappedBytes),
                    systemImage: "externaldrive",
                    theme: theme
                )
            }
            if let itemsScanned = activity.itemsScanned {
                stat(
                    isCompact ? itemsScanned.formatted() : "\(itemsScanned.formatted()) items",
                    systemImage: "doc.on.doc",
                    theme: theme
                )
            }
            if let startedAt = activity.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    stat(
                        StorageFormatters.duration(max(context.date.timeIntervalSince(startedAt), 0)),
                        systemImage: "clock",
                        theme: theme
                    )
                }
            }
            if !isCompact { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ text: String, systemImage: String, theme: SpaceTheme) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.accent)
            Text(text)
                .lineLimit(1)
        }
        .font(isCompact ? .caption2.weight(.medium).monospacedDigit() : .callout.weight(.medium).monospacedDigit())
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, isCompact ? 7 : 11)
        .padding(.vertical, isCompact ? 5 : 7)
        .background(theme.elevatedSurface.opacity(0.7), in: Capsule())
    }

    private func accessibilityText(_ activity: ScanActivity) -> String {
        let state = activity.isQueued ? "queued" : "in progress"
        let fraction = activity.fraction.map { ", \(StorageFormatters.percent($0))" } ?? ""
        return "\(activity.title) \(state)\(fraction), \(activity.status), \(activity.detail)"
    }
}
