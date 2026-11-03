import SwiftUI

struct AICodingToolsViewActions {
    let selectTool: (AICodingToolID) -> Void
    let analyze: () -> Void
    let showInFinder: (URL) -> Void
    let openInTerminal: (URL) -> Void
    let inspect: (FileNode) -> Void
}

struct AICodingToolsView: View {
    @Bindable var store: AICodingToolsStore
    @Environment(\.colorScheme) private var colorScheme
    let isInBatch: Bool
    let actions: AICodingToolsViewActions

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            header(theme: theme)

            switch store.state {
            case .idle:
                if isInBatch {
                    runningState(theme: theme)
                } else {
                    emptyState(theme: theme)
                }
            case .running(let previousReport):
                if let previousReport {
                    refreshableReport { reportView(previousReport, theme: theme) }
                } else {
                    runningState(theme: theme)
                }
            case .completed(let report):
                refreshableReport { reportView(report, theme: theme) }
            case .failed(let message, let previousReport):
                if let previousReport {
                    refreshableReport { reportView(previousReport, theme: theme, errorMessage: message) }
                } else {
                    failureState(message: message, theme: theme)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    private func header(theme: SpaceTheme) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("AI Coding Tools")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.primaryText)
                Text("Find installed versions and measure local storage used by coding tools.")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            if let report = store.state.report {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(StorageFormatters.bytes(report.totalSize))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.primaryText)
                    Text(
                        "\(report.installationCount.formatted()) installations · "
                            + "\(report.itemCount.formatted()) items · \(StorageFormatters.duration(report.duration))"
                            + " · Updated \(report.completedAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                        .font(.caption)
                        .foregroundStyle(theme.tertiaryText)
                    if report.issueCount > 0 {
                        Label("\(report.issueCount) coverage issues", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.warning)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Total \(StorageFormatters.bytes(report.totalSize)), "
                        + "\(report.installationCount) installations, \(report.itemCount) items, "
                        + "analyzed in \(StorageFormatters.duration(report.duration)), "
                        + "\(report.issueCount) coverage issues"
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func emptyState(theme: SpaceTheme) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)

                    Text("See what coding tools are installed and stored")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(
                        "SpaceLens identifies conventional app and CLI installations for Cursor, Claude Code, "
                            + "Codex, Google Antigravity, OpenCode, and T3 Code, then measures their known storage locations."
                    )
                    .font(.body)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)

                    Button {
                        actions.analyze()
                    } label: {
                        Label("Analyze Coding Tools", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .controlSize(.large)
                }
                .padding(28)
                .frame(maxWidth: 760)
                .spacePanel()

                supportedTools(theme: theme)

                metadataNotice(theme: theme)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func refreshableReport<Report: View>(
        @ViewBuilder report: () -> Report
    ) -> some View {
        let report = report()
        return FoldableScanFacts(
            topic: .codingTools,
            source: store.isRunning || isInBatch ? .analysis(.aiCodingTools) : nil
        ) {
            report
        }
    }

    private func runningState(theme: SpaceTheme) -> some View {
        ScanFactsView(topic: .codingTools, source: .analysis(.aiCodingTools)) {
            metadataNotice(theme: theme)
        }
    }

    private func failureState(message: String, theme: SpaceTheme) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text("Analysis could not finish")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Button("Try Again") { actions.analyze() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reportView(
        _ report: AICodingToolsReport,
        theme: SpaceTheme,
        errorMessage: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            if let errorMessage {
                analysisBanner(
                    icon: "exclamationmark.triangle.fill",
                    message: errorMessage,
                    color: theme.warning,
                    theme: theme
                )
            }

            HStack(spacing: 12) {
                toolRanking(report: report, theme: theme)
                    .frame(width: AppLayoutMetrics.analysisListColumnWidth)

                Divider()

                if let tool = selectedTool(in: report) {
                    AICodingToolDetail(
                        tool: tool,
                        totalSize: report.totalSize,
                        actions: actions
                    )
                        .id(tool.id)
                }
            }
            .padding(12)
        }
        .onAppear { selectDefaultTool(in: report) }
        .onChange(of: report.startedAt) { selectDefaultTool(in: report) }
    }

    private func toolRanking(report: AICodingToolsReport, theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tools")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("Largest first")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 4)

            ForEach(report.rankedTools) { tool in
                Button {
                    actions.selectTool(tool.id)
                } label: {
                    AICodingToolRow(
                        tool: tool,
                        totalSize: report.totalSize,
                        isSelected: store.selectedToolID == tool.id
                    )
                }
                .buttonStyle(.plain)
                .hoverFeedback(.row(cornerRadius: 9))
                .accessibilityAddTraits(store.selectedToolID == tool.id ? .isSelected : [])
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .spacePanel()
    }

    private func supportedTools(theme: SpaceTheme) -> some View {
        HStack(spacing: 10) {
            ForEach(AICodingToolsCatalog.supportedTools) { tool in
                BrandChipLabel(
                    title: tool.displayName,
                    logo: tool.logo,
                    systemImage: tool.systemImage,
                    tint: theme.accent
                )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(theme.border, lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func metadataNotice(theme: SpaceTheme) -> some View {
        Label(
            "SpaceLens reads filesystem metadata plus app and package manifests needed to identify "
                + "installations and versions. It reads Claude's project registry only to label encoded folders, "
                + "and does not open conversations, project files, databases, or credentials.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(theme.tertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 680)
        .accessibilityElement(children: .combine)
    }

    private func analysisBanner(
        icon: String,
        message: String,
        color: Color,
        theme: SpaceTheme
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(color.opacity(0.09))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func selectedTool(in report: AICodingToolsReport) -> AICodingToolReport? {
        report.tools.first { $0.id == store.selectedToolID } ?? report.rankedTools.first
    }

    private func selectDefaultTool(in report: AICodingToolsReport) {
        if !report.tools.contains(where: { $0.id == store.selectedToolID }),
           let id = report.rankedTools.first?.id {
            store.selectTool(id)
        }
    }
}
