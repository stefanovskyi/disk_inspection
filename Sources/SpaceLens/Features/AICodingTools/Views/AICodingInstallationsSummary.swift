import SwiftUI

struct AICodingInstallationsSummary: View {
    @Environment(\.colorScheme) private var colorScheme
    let installations: [AICodingToolInstallation]
    let showInFinder: (URL) -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Installations")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(installationCount)
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
            }

            if installations.isEmpty {
                Label(
                    "No recognized app or CLI installation was found in conventional locations.",
                    systemImage: "questionmark.folder"
                )
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .padding(.vertical, 8)
            } else {
                ForEach(installations) { installation in
                    AICodingInstallationCard(
                        installation: installation,
                        showInFinder: showInFinder
                    )
                }
            }
        }
        .padding(14)
        .spacePanel()
    }

    private var installationCount: String {
        "\(installations.count) " + (installations.count == 1 ? "installation" : "installations")
    }
}

private struct AICodingInstallationCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let installation: AICodingToolInstallation
    let showInFinder: (URL) -> Void
    @State private var isExpanded = false

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ZStack(alignment: .topTrailing) {
            Button(action: toggleExpanded) {
                VStack(alignment: .leading, spacing: 9) {
                    summaryContent(theme: theme)

                    if isExpanded {
                        Divider()
                            .overlay(theme.border)

                        detailsContent(theme: theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    theme.elevatedSurface.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(installation.displayName), \(installation.surface.displayName), \(versionSummary)"
            )
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide installation details")

            Button {
                showInFinder(installation.rootURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .padding(11)
            .help("Show installation in Finder")
            .accessibilityLabel("Show \(installation.displayName) installation in Finder")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func summaryContent(theme: SpaceTheme) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: installation.surface.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 28, height: 28)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(installation.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(installation.surface.displayName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.surface, in: Capsule())
                }
                Text(versionSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 36)
        }
    }

    @ViewBuilder
    private func detailsContent(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                if let method = installation.installMethod {
                    Label(method.value.displayName, systemImage: "shippingbox")
                } else {
                    Label("Install method unknown", systemImage: "shippingbox")
                }
                if installation.isOnProcessPath {
                    Label("On SpaceLens PATH", systemImage: "link")
                }
            }
            .foregroundStyle(theme.tertiaryText)

            if let installedOrUpdatedAt = installation.installedOrUpdatedAt {
                Label(
                    "Homebrew installed/updated "
                        + installedOrUpdatedAt.value.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ),
                    systemImage: "clock.arrow.circlepath"
                )
                .foregroundStyle(theme.secondaryText)
            }

            if !installation.entryPoints.isEmpty {
                Text("Commands: " + installation.entryPoints.map(\.name).joined(separator: ", "))
                    .foregroundStyle(theme.secondaryText)
            }

            if olderReleaseCount > 0 {
                Label(
                    "\(olderReleaseCount) older "
                        + (olderReleaseCount == 1 ? "release" : "releases")
                        + " retained",
                    systemImage: "clock"
                )
                .foregroundStyle(theme.secondaryText)
            }

            pathRow("Installation", url: installation.rootURL, theme: theme)

            ForEach(installation.entryPoints) { entryPoint in
                pathRow("Command \(entryPoint.name)", url: entryPoint.url, theme: theme)
            }

            ForEach(installation.components) { component in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(component.name)
                        .foregroundStyle(theme.secondaryText)
                    Spacer(minLength: 8)
                    Text(component.version?.value ?? "Version unknown")
                        .foregroundStyle(theme.tertiaryText)
                }
                .font(.caption)
                pathRow("Bundled component", url: component.url, theme: theme)
            }

            ForEach(installation.retainedReleases) { release in
                pathRow(
                    release.isActive
                        ? "Active release \(release.version)"
                        : "Retained release \(release.version)",
                    url: release.url,
                    theme: theme
                )
            }

            if let observed = installation.observedFileDate {
                Text(
                    "Observed file date "
                        + observed.value.formatted(date: .abbreviated, time: .shortened)
                        + " · not a proven update date"
                )
                .font(.caption)
                .foregroundStyle(theme.tertiaryText)
            }

            ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                pathRow(
                    "\(item.label) evidence · \(item.source.kind.displayName)",
                    url: item.source.url,
                    theme: theme
                )
            }

            ForEach(installation.notes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleExpanded() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        }
    }

    private var versionSummary: String {
        guard let version = installation.version?.value else { return "Version unknown" }
        if let build = installation.build?.value, build != version {
            return "Version \(version) · build \(build)"
        }
        return "Version \(version)"
    }

    private var olderReleaseCount: Int {
        installation.retainedReleases.filter { !$0.isActive }.count
    }

    private var evidence: [(label: String, source: AICodingInstallationEvidenceSource)] {
        var values: [(String, AICodingInstallationEvidenceSource)] = []
        if let fact = installation.version { values.append(("Version", fact.source)) }
        if let fact = installation.build { values.append(("Build", fact.source)) }
        if let fact = installation.installMethod { values.append(("Install method", fact.source)) }
        if let fact = installation.installedOrUpdatedAt { values.append(("Install/update date", fact.source)) }
        var seen: Set<String> = []
        return values.filter {
            seen.insert("\($0.0)|\($0.1.kind.rawValue)|\($0.1.url.path)").inserted
        }
    }

    private func pathRow(_ label: String, url: URL, theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.tertiaryText)
            Text(url.path)
                .font(.caption2.monospaced())
                .foregroundStyle(theme.secondaryText)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
