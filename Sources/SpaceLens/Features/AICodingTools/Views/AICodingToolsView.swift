import SwiftUI

struct AICodingToolsViewActions {
    let chooseProjectRoot: () -> Void
    let showInFinder: (URL) -> Void
    let openInTerminal: (URL) -> Void
    let inspect: (FileNode) -> Void
}

struct AICodingToolsView: View {
    @Bindable var store: AICodingToolsStore
    @Environment(\.colorScheme) private var colorScheme
    let actions: AICodingToolsViewActions

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            header(theme: theme)

            switch store.state {
            case .idle:
                emptyState(theme: theme)
            case .running(let previousReport):
                if let previousReport {
                    reportView(previousReport, theme: theme, progressMessage: progressMessage)
                } else {
                    runningState(theme: theme)
                }
            case .completed(let report):
                reportView(report, theme: theme)
            case .failed(let message, let previousReport):
                if let previousReport {
                    reportView(previousReport, theme: theme, errorMessage: message)
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
                Text("Measure the local storage footprint left by coding agents and editors.")
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
                        "\(report.itemCount.formatted()) items · \(StorageFormatters.duration(report.duration))"
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
                        + "\(report.itemCount) items, analyzed in \(StorageFormatters.duration(report.duration)), "
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

                    Text("See what your coding tools store")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    Text(
                        "SpaceLens measures known storage locations for Cursor, Claude Code, Codex, "
                            + "and Google Antigravity, then shows each location as an expandable folder tree."
                    )
                    .font(.body)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)

                    Button {
                        store.analyze()
                    } label: {
                        Label("Analyze Tool Storage", systemImage: "play.fill")
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

    private func runningState(theme: SpaceTheme) -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Analyzing AI coding tool storage")

            Text(progressTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.primaryText)

            Text(progressMessage)
                .font(.callout.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let fraction = store.progress.fractionCompleted {
                ProgressView(value: fraction)
                    .frame(maxWidth: 430)
                    .tint(theme.accent)
                    .accessibilityValue(StorageFormatters.percent(fraction))
            }

            HStack(spacing: 18) {
                Label(
                    StorageFormatters.bytes(store.progress.mappedBytes),
                    systemImage: "externaldrive"
                )
                Label(
                    "\(store.progress.itemsScanned.formatted()) items",
                    systemImage: "doc.on.doc"
                )
                analysisElapsedLabel
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(theme.secondaryText)

            Button("Cancel") { store.cancelPreservingReport() }
                .buttonStyle(.bordered)

            metadataNotice(theme: theme)
                .padding(.top, 8)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button("Try Again") { store.analyze() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reportView(
        _ report: AICodingToolsReport,
        theme: SpaceTheme,
        progressMessage: String? = nil,
        errorMessage: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            if let progressMessage {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    analysisBanner(
                        icon: "arrow.triangle.2.circlepath",
                        message: progressMessage + " · " + elapsedText(at: context.date),
                        color: theme.accent,
                        showsProgress: true,
                        theme: theme
                    )
                }
            } else if let errorMessage {
                analysisBanner(
                    icon: "exclamationmark.triangle.fill",
                    message: errorMessage,
                    color: theme.warning,
                    showsProgress: false,
                    theme: theme
                )
            }

            HStack(spacing: 12) {
                toolRanking(report: report, theme: theme)
                    .frame(width: 300)

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
                    store.selectTool(tool.id)
                } label: {
                    AICodingToolRow(
                        tool: tool,
                        totalSize: report.totalSize,
                        isSelected: store.selectedToolID == tool.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.selectedToolID == tool.id ? .isSelected : [])
            }

            Spacer(minLength: 8)

            projectRoots(theme: theme)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .spacePanel()
    }

    private func supportedTools(theme: SpaceTheme) -> some View {
        HStack(spacing: 10) {
            ForEach(AICodingToolsCatalog.supportedTools) { tool in
                Label(tool.displayName, systemImage: tool.systemImage)
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

    private func projectRoots(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Project roots")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Button {
                    actions.chooseProjectRoot()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a project root")
                .accessibilityLabel("Add project root")
            }

            if store.projectRoots.isEmpty {
                Text("Add projects to include Claude Code worktrees stored inside them.")
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(store.projectRoots) { folder in
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(theme.accent)
                        Text(folder.url.lastPathComponent)
                            .lineLimit(1)
                            .help(folder.url.path)
                        Spacer(minLength: 2)
                        Button {
                            store.removeProjectRoot(folder)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(theme.tertiaryText)
                        .help("Remove project root")
                        .accessibilityLabel("Remove \(folder.url.lastPathComponent)")
                    }
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(theme.elevatedSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metadataNotice(theme: SpaceTheme) -> some View {
        Label(
            "Metadata only: SpaceLens measures allocated file size and modification dates. "
                + "It does not open conversations, databases, source files, or credentials.",
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
        showsProgress: Bool,
        theme: SpaceTheme
    ) -> some View {
        HStack(spacing: 9) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
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

    private var progressTitle: String {
        if let tool = store.progress.currentTool {
            return "Analyzing \(tool.displayName)"
        }
        return "Preparing analysis"
    }

    private var analysisElapsedLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label(elapsedText(at: context.date), systemImage: "clock")
        }
    }

    private func elapsedText(at date: Date) -> String {
        guard let startedAt = store.startedAt else { return "0 sec" }
        return StorageFormatters.duration(max(date.timeIntervalSince(startedAt), 0))
    }

    private var progressMessage: String {
        let progress = store.progress
        if !progress.currentLocationName.isEmpty {
            let path = progress.currentPath.isEmpty ? "" : " · \(progress.currentPath)"
            return "\(progress.currentLocationName)\(path)"
        }
        return "Finding known tool storage locations…"
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
