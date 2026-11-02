import SwiftUI

struct DeveloperStorageViewActions {
    let analyze: () -> Void
    let showInFinder: (URL) -> Void
    let openInTerminal: (URL) -> Void
    let inspectDirectory: (URL) -> Void
}

struct DeveloperStorageView: View {
    @Bindable var store: DeveloperStorageStore
    @Environment(\.colorScheme) private var colorScheme
    let isInBatch: Bool
    let actions: DeveloperStorageViewActions

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
                    Button { actions.analyze() } label: {
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
                        BrandChipLabel(
                            title: ecosystem.displayName,
                            logo: ecosystem.logo,
                            systemImage: ecosystem.systemImage,
                            tint: theme.accent
                        )
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

    private func refreshableReport<Report: View>(
        @ViewBuilder report: () -> Report
    ) -> some View {
        let report = report()
        return FoldableScanFacts(
            topic: .developerStorage,
            source: store.isRunning || isInBatch ? .analysis(.developerStorage) : nil
        ) {
            report
        }
    }

    private func runningState(theme: SpaceTheme) -> some View {
        ScanFactsView(topic: .developerStorage, source: .analysis(.developerStorage))
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
            Button("Try Again") { actions.analyze() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reportView(
        _ report: DeveloperStorageReport,
        theme: SpaceTheme,
        errorMessage: String? = nil
    ) -> some View {
        VStack(spacing: 0) {
            if let errorMessage {
                statusBanner(message: errorMessage, theme: theme)
            }
            HStack(spacing: 12) {
                ecosystemRanking(report: report, theme: theme)
                    .frame(width: AppLayoutMetrics.analysisListColumnWidth)
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

    private func statusBanner(message: String, theme: SpaceTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
            Text(message).font(.caption.weight(.medium)).foregroundStyle(theme.secondaryText).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider() }
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
                BrandLogoImage(logo: ecosystem.logo, size: 24)
                Text(ecosystem.displayName).font(.callout.weight(.semibold)).foregroundStyle(theme.primaryText)
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
