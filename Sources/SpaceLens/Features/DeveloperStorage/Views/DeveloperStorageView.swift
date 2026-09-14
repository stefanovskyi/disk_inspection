import SwiftUI

struct DeveloperStorageViewActions {
    let showInFinder: (URL) -> Void
    let openInTerminal: (URL) -> Void
    let inspectDirectory: (URL) -> Void
}

struct DeveloperStorageView: View {
    @Bindable var store: DeveloperStorageStore
    @Environment(\.colorScheme) private var colorScheme
    let actions: DeveloperStorageViewActions

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
            Image(systemName: "hammer.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Developer Storage")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.primaryText)
                Text("Measure dependencies, environments, build data, package stores, and toolchains.")
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
                        "\(report.locationCount.formatted()) locations · \(report.itemCount.formatted()) items · "
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
                    Text("See where development work uses space")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(
                        "SpaceLens automatically searches your home folder for generated dependencies, environments, "
                            + "caches, and build outputs, then separates projects, tool-managed storage, shared locations, "
                            + "and artifacts whose owner cannot be verified. Add a projects folder for external locations."
                    )
                    .font(.body)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 650)
                    Button { store.analyze() } label: {
                        Label("Analyze Developer Storage", systemImage: "play.fill")
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
                    ForEach(DeveloperEcosystemID.allCases) { ecosystem in
                        Label(ecosystem.displayName, systemImage: ecosystem.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(theme.surface, in: Capsule())
                            .overlay { Capsule().stroke(theme.border, lineWidth: 1) }
                    }
                }

                Label(
                    "Reads filesystem metadata and a few bounded marker files. It never runs tools, changes files, or claims that measured storage is reclaimable.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func runningState(theme: SpaceTheme) -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Analyzing developer storage")
            Text(progressTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Text(progressMessage)
                .font(.callout.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let fraction = store.progress.fractionCompleted {
                ProgressView(value: fraction).frame(maxWidth: 430).tint(theme.accent)
            }
            HStack(spacing: 18) {
                Label(StorageFormatters.bytes(store.progress.mappedBytes), systemImage: "externaldrive")
                Label("\(store.progress.itemsScanned.formatted()) items", systemImage: "doc.on.doc")
                Label("\(store.progress.discoveredArtifacts.formatted()) artifacts", systemImage: "folder.badge.gearshape")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        StorageFormatters.duration(context.date.timeIntervalSince(store.startedAt ?? context.date)),
                        systemImage: "clock"
                    )
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(theme.secondaryText)
            Button("Cancel") { store.cancelPreservingReport() }.buttonStyle(.bordered)
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(message: String, theme: SpaceTheme) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(theme.warning)
            Text("Analysis could not finish").font(.title3.weight(.semibold))
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
        _ report: DeveloperStorageReport,
        theme: SpaceTheme,
        progressMessage: String? = nil,
        errorMessage: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            if let progressMessage {
                statusBanner(message: progressMessage, warning: false, theme: theme)
            } else if let errorMessage {
                statusBanner(message: errorMessage, warning: true, theme: theme)
            }
            HStack(spacing: 12) {
                ecosystemRanking(report: report, theme: theme).frame(width: 300)
                Divider()
                if let ecosystem = selectedEcosystem(in: report) {
                    DeveloperEcosystemDetail(ecosystem: ecosystem, totalSize: report.totalSize, actions: actions)
                        .id(ecosystem.id)
                }
            }
            .padding(12)
        }
        .onAppear { selectDefaultEcosystem(in: report) }
        .onChange(of: report.startedAt) { selectDefaultEcosystem(in: report) }
    }

    private func ecosystemRanking(report: DeveloperStorageReport, theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ecosystems").font(.headline).foregroundStyle(theme.primaryText)
                Spacer()
                Text("Unique size").font(.caption).foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 4)
            ForEach(report.rankedEcosystems) { ecosystem in
                Button { store.selectEcosystem(ecosystem.id) } label: {
                    DeveloperEcosystemRow(
                        ecosystem: ecosystem,
                        totalSize: report.totalSize,
                        isSelected: store.selectedEcosystemID == ecosystem.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.selectedEcosystemID == ecosystem.id ? .isSelected : [])
            }
            Spacer()
        }
        .padding(12)
        .spacePanel()
    }

    private func statusBanner(message: String, warning: Bool, theme: SpaceTheme) -> some View {
        HStack(spacing: 8) {
            if !warning { ProgressView().controlSize(.small) }
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .foregroundStyle(warning ? theme.warning : theme.accent)
            Text(message).font(.caption.weight(.medium)).foregroundStyle(theme.secondaryText).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var progressTitle: String {
        if let ecosystem = store.progress.currentEcosystem { return "Analyzing \(ecosystem.displayName)" }
        return "Discovering developer artifacts…"
    }

    private var progressMessage: String {
        var parts: [String] = []
        if let name = store.progress.currentLocationName { parts.append(name) }
        if store.progress.totalLocations > 0 {
            parts.append("\(store.progress.completedLocations) of \(store.progress.totalLocations) locations")
        }
        if let path = store.progress.currentPath { parts.append(path) }
        return parts.isEmpty ? "Resolving recognized locations" : parts.joined(separator: " · ")
    }

    private func selectedEcosystem(in report: DeveloperStorageReport) -> DeveloperEcosystemReport? {
        if let id = store.selectedEcosystemID,
           let ecosystem = report.ecosystems.first(where: { $0.id == id }) { return ecosystem }
        return report.rankedEcosystems.first
    }

    private func selectDefaultEcosystem(in report: DeveloperStorageReport) {
        if let id = store.selectedEcosystemID, report.ecosystems.contains(where: { $0.id == id }) { return }
        if let first = report.rankedEcosystems.first { store.selectEcosystem(first.id) }
    }
}

private struct DeveloperEcosystemRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let ecosystem: DeveloperEcosystemReport
    let totalSize: Int64
    let isSelected: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let fraction = totalSize > 0 ? Double(ecosystem.uniqueSize) / Double(totalSize) : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: ecosystem.systemImage).foregroundStyle(theme.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ecosystem.displayName).font(.callout.weight(.semibold)).foregroundStyle(theme.primaryText)
                    Text("Projects \(StorageFormatters.bytes(ecosystem.projectSize)) · Tool-managed \(StorageFormatters.bytes(ecosystem.toolManagedSize))")
                        .font(.caption2).foregroundStyle(theme.tertiaryText).lineLimit(1)
                    Text("Shared \(StorageFormatters.bytes(ecosystem.sharedSize)) · Unattributed \(StorageFormatters.bytes(ecosystem.unattributedSize))")
                        .font(.caption2).foregroundStyle(theme.tertiaryText).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(StorageFormatters.bytes(ecosystem.uniqueSize))
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(theme.primaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.elevatedSurface)
                    Capsule().fill(theme.accent).frame(width: max(ecosystem.uniqueSize > 0 ? 3 : 0, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? theme.selectionSurface : Color.clear)
                .overlay { if isSelected { RoundedRectangle(cornerRadius: 9).stroke(theme.selectionBorder) } }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DeveloperStorageToolbarStatus: View {
    let progress: DeveloperStorageProgress

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text(progress.currentEcosystem?.displayName ?? "Discovering developer storage")
                .font(.caption.weight(.medium)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analyzing developer storage")
    }
}
