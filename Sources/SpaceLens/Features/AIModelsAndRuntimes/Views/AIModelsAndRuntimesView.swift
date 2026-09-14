import SwiftUI

struct AIModelsViewActions {
    let analyze: () -> Void
    let showInFinder: (URL) -> Void
    let openInTerminal: (URL) -> Void
    let inspectDirectory: (URL) -> Void
}

struct AIModelsAndRuntimesView: View {
    @Bindable var store: AIModelsAndRuntimesStore
    @Environment(\.colorScheme) private var colorScheme
    let actions: AIModelsViewActions

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
        HStack(spacing: 14) {
            Image(systemName: "cpu")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Models")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.primaryText)
                Text("Find local model weights, inference engines, caches, and supporting data.")
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
                        "\(report.modelCount.formatted()) models · \(report.itemCount.formatted()) items · "
                            + StorageFormatters.duration(report.duration)
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
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text("See where local AI models use space")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(
                        "SpaceLens recognizes Ollama, LM Studio, llama.cpp, Hugging Face Hub caches, "
                            + "and model files in selected local folders. Analysis is read-only."
                    )
                    .font(.body)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
                    Button {
                        actions.analyze()
                    } label: {
                        Label("Analyze AI Models", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .controlSize(.large)
                }
                .padding(28)
                .frame(maxWidth: 780)
                .spacePanel()

                HStack(spacing: 9) {
                    ForEach(AIModelsCatalog.supportedRuntimes) { runtime in
                        Label(runtime.displayName, systemImage: runtime.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(theme.surface, in: Capsule())
                            .overlay { Capsule().stroke(theme.border, lineWidth: 1) }
                    }
                }

                privacyNotice(theme: theme)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func runningState(theme: SpaceTheme) -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Analyzing AI models and runtimes")
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
            }
            HStack(spacing: 18) {
                Label(StorageFormatters.bytes(store.progress.mappedBytes), systemImage: "externaldrive")
                Label("\(store.progress.itemsScanned.formatted()) items", systemImage: "doc.on.doc")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(elapsedText(at: context.date), systemImage: "clock")
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(theme.secondaryText)
            Button("Cancel") { store.cancelPreservingReport() }
                .buttonStyle(.bordered)
            privacyNotice(theme: theme)
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
            Button("Try Again") { actions.analyze() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reportView(
        _ report: AIModelsAndRuntimesReport,
        theme: SpaceTheme,
        progressMessage: String? = nil,
        errorMessage: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            if let progressMessage {
                statusBanner(
                    icon: "arrow.triangle.2.circlepath",
                    message: progressMessage,
                    color: theme.accent,
                    showsProgress: true,
                    theme: theme
                )
            } else if let errorMessage {
                statusBanner(
                    icon: "exclamationmark.triangle.fill",
                    message: errorMessage,
                    color: theme.warning,
                    showsProgress: false,
                    theme: theme
                )
            }
            HStack(spacing: 12) {
                runtimeRanking(report: report, theme: theme)
                    .frame(width: 300)
                Divider()
                if let runtime = selectedRuntime(in: report) {
                    AIModelRuntimeDetail(runtime: runtime, totalSize: report.totalSize, actions: actions)
                        .id(runtime.id)
                }
            }
            .padding(12)
        }
        .onAppear { selectDefaultRuntime(in: report) }
        .onChange(of: report.startedAt) { selectDefaultRuntime(in: report) }
    }

    private func runtimeRanking(
        report: AIModelsAndRuntimesReport,
        theme: SpaceTheme
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Runtimes & stores")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("Largest first")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 4)
            ForEach(report.rankedRuntimes) { runtime in
                Button { store.selectRuntime(runtime.id) } label: {
                    AIModelRuntimeRow(
                        runtime: runtime,
                        totalSize: report.totalSize,
                        isSelected: store.selectedRuntimeID == runtime.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.selectedRuntimeID == runtime.id ? .isSelected : [])
            }
            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .spacePanel()
    }

    private func statusBanner(
        icon: String,
        message: String,
        color: Color,
        showsProgress: Bool,
        theme: SpaceTheme
    ) -> some View {
        HStack(spacing: 8) {
            if showsProgress { ProgressView().controlSize(.small) }
            Image(systemName: icon).foregroundStyle(color)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func privacyNotice(theme: SpaceTheme) -> some View {
        Label(
            "Reads file metadata and bounded model headers only. It never loads models, starts runtimes, or deletes files.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(theme.tertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 650)
    }

    private var progressTitle: String {
        guard let runtime = store.progress.currentRuntime else { return "Preparing analysis…" }
        return "Analyzing \(runtime.displayName)"
    }

    private var progressMessage: String {
        var parts: [String] = []
        if let name = store.progress.currentLocationName { parts.append(name) }
        if store.progress.totalLocations > 0 {
            parts.append("\(store.progress.completedLocations) of \(store.progress.totalLocations) locations")
        }
        if let path = store.progress.currentPath { parts.append(path) }
        return parts.isEmpty ? "Discovering known locations" : parts.joined(separator: " · ")
    }

    private func elapsedText(at date: Date) -> String {
        StorageFormatters.duration(date.timeIntervalSince(store.startedAt ?? date))
    }

    private func selectedRuntime(in report: AIModelsAndRuntimesReport) -> AIModelRuntimeReport? {
        if let id = store.selectedRuntimeID,
           let runtime = report.runtimes.first(where: { $0.id == id }) { return runtime }
        return report.rankedRuntimes.first
    }

    private func selectDefaultRuntime(in report: AIModelsAndRuntimesReport) {
        if let id = store.selectedRuntimeID, report.runtimes.contains(where: { $0.id == id }) { return }
        if let first = report.rankedRuntimes.first { store.selectRuntime(first.id) }
    }
}

private struct AIModelRuntimeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let runtime: AIModelRuntimeReport
    let totalSize: Int64
    let isSelected: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let fraction = totalSize > 0 ? Double(runtime.size) / Double(totalSize) : 0
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: runtime.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(runtime.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(runtime.countDescription)
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(StorageFormatters.bytes(runtime.size))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.primaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.elevatedSurface)
                    Capsule().fill(theme.accent)
                        .frame(width: max(runtime.size > 0 ? 3 : 0, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? theme.selectionSurface : Color.clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9).stroke(theme.selectionBorder, lineWidth: 1)
                    }
                }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(runtime.displayName), \(runtime.countDescription), \(StorageFormatters.bytes(runtime.size))"
        )
    }
}

struct AIModelsToolbarStatus: View {
    let progress: AIModelsProgress

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text(progress.currentRuntime?.displayName ?? "Analyzing models")
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing AI models and runtimes")
    }
}
