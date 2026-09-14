import SwiftUI

struct DeveloperEcosystemDetail: View {
    @Environment(\.colorScheme) private var colorScheme
    let ecosystem: DeveloperEcosystemReport
    let totalSize: Int64
    let actions: DeveloperStorageViewActions
    @State private var filter: ScopeFilter = .all
    @State private var expandedProjectIDs: Set<String> = []
    @State private var expandedLocationIDs: Set<String> = []

    private enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case projects = "Projects"
        case shared = "Shared"
        var id: String { rawValue }
    }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(theme: theme)
                composition(theme: theme)
                locations(theme: theme)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func header(theme: SpaceTheme) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ecosystem.systemImage)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 46, height: 46)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(ecosystem.displayName).font(.title2.weight(.bold))
                Text("Projects \(StorageFormatters.bytes(ecosystem.projectSize)) · Shared \(StorageFormatters.bytes(ecosystem.sharedSize)) · \(ecosystem.itemCount.formatted()) items")
                    .font(.callout).foregroundStyle(theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(StorageFormatters.bytes(ecosystem.uniqueSize)).font(.title2.weight(.semibold).monospacedDigit())
                if totalSize > 0 {
                    Text(StorageFormatters.percent(Double(ecosystem.uniqueSize) / Double(totalSize)))
                        .font(.caption).foregroundStyle(theme.tertiaryText)
                }
            }
        }
        .foregroundStyle(theme.primaryText)
        .padding(16)
        .spacePanel()
    }

    private func composition(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage composition").font(.headline).foregroundStyle(theme.primaryText)
            if ecosystem.breakdowns.isEmpty {
                Text("No recognized storage was measured.").font(.callout).foregroundStyle(theme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 8)], spacing: 8) {
                    ForEach(ecosystem.breakdowns) { breakdown in
                        HStack(spacing: 8) {
                            Image(systemName: breakdown.kind.systemImage).foregroundStyle(theme.accent).frame(width: 18)
                            Text(breakdown.kind.displayName).font(.caption).foregroundStyle(theme.secondaryText).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(StorageFormatters.bytes(breakdown.uniqueSize))
                                .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(theme.primaryText)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(theme.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(14)
        .spacePanel()
    }

    private func locations(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Projects & shared storage").font(.headline).foregroundStyle(theme.primaryText)
                Spacer()
                Picker("Scope", selection: $filter) {
                    ForEach(ScopeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 230)
            }

            if filteredLocations.isEmpty {
                Label("No matching locations were found.", systemImage: "folder.badge.questionmark")
                    .font(.callout).foregroundStyle(theme.secondaryText).padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 8) {
                    locationGroups(theme: theme)
                }
            }
        }
        .padding(14)
        .spacePanel()
    }

    private var filteredLocations: [DeveloperStorageLocation] {
        let locations: [DeveloperStorageLocation]
        switch filter {
        case .all: locations = ecosystem.locations
        case .projects: locations = ecosystem.locations.filter { $0.scope == .project }
        case .shared: locations = ecosystem.locations.filter { $0.scope == .shared }
        }
        return locations.sorted {
            $0.uniqueSize == $1.uniqueSize ? $0.name < $1.name : $0.uniqueSize > $1.uniqueSize
        }
    }

    @ViewBuilder
    private func locationGroups(theme: SpaceTheme) -> some View {
        if filter != .shared {
            ForEach(ecosystem.projects) { project in
                DeveloperProjectRow(
                    project: project,
                    isExpanded: projectExpansionBinding(for: project.id),
                    expandedLocationIDs: $expandedLocationIDs,
                    actions: actions
                )
            }
        }
        if filter != .projects, !ecosystem.sharedLocations.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label("Shared locations", systemImage: "internaldrive")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 3)
                ForEach(ecosystem.sharedLocations) { location in
                    locationRow(location)
                }
            }
        }
    }

    private func locationRow(_ location: DeveloperStorageLocation) -> some View {
        DeveloperStorageLocationRow(
            location: location,
            isExpanded: expansionBinding(for: location.id),
            showsScope: true,
            actions: actions
        )
    }

    private func projectExpansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedProjectIDs.contains(id) },
            set: { expanded in
                if expanded { expandedProjectIDs.insert(id) } else { expandedProjectIDs.remove(id) }
            }
        )
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedLocationIDs.contains(id) },
            set: { expanded in
                if expanded { expandedLocationIDs.insert(id) } else { expandedLocationIDs.remove(id) }
            }
        )
    }
}

private struct DeveloperProjectRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let project: DeveloperProjectReport
    @Binding var isExpanded: Bool
    @Binding var expandedLocationIDs: Set<String>
    let actions: DeveloperStorageViewActions

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Button { isExpanded.toggle() } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(theme.accent)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(project.name)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.primaryText)
                                    .lineLimit(1)
                                if project.issueCount > 0 {
                                    Label("\(project.issueCount)", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(theme.warning)
                                }
                            }
                            Text(project.url.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(projectSummary)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(StorageFormatters.bytes(project.uniqueSize))
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(theme.primaryText)
                        }
                    }
                    .padding(.leading, 11)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(project.name), \(project.url.path), \(StorageFormatters.bytes(project.uniqueSize))")
                .accessibilityValue("\(projectSummary), \(isExpanded ? "expanded" : "collapsed")")
                .accessibilityHint(isExpanded ? "Collapse project artifacts" : "Expand to show project artifacts")

                Menu {
                    Button("Reveal in Finder") { actions.showInFinder(project.url) }
                    Button("Open in Terminal") { actions.openInTerminal(project.url) }
                    Button("Inspect Storage Map") { actions.inspectDirectory(project.url) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.top, 10)
                .padding(.trailing, 9)
                .help("Project actions")
                .accessibilityLabel("Actions for \(project.name)")
            }

            if isExpanded {
                Divider().padding(.leading, 14)
                VStack(spacing: 8) {
                    ForEach(project.locations) { location in
                        DeveloperStorageLocationRow(
                            location: location,
                            isExpanded: locationExpansionBinding(for: location.id),
                            showsScope: false,
                            actions: actions
                        )
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
            }
        }
        .background(theme.elevatedSurface.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(theme.border.opacity(0.9)) }
    }

    private var projectSummary: String {
        let artifacts = project.artifactCount == 1 ? "1 artifact" : "\(project.artifactCount.formatted()) artifacts"
        return "\(artifacts) · \(project.itemCount.formatted()) items"
    }

    private func locationExpansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedLocationIDs.contains(id) },
            set: { expanded in
                if expanded { expandedLocationIDs.insert(id) } else { expandedLocationIDs.remove(id) }
            }
        )
    }
}

private struct DeveloperStorageLocationRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let location: DeveloperStorageLocation
    @Binding var isExpanded: Bool
    let showsScope: Bool
    let actions: DeveloperStorageViewActions

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Button { if expandable { isExpanded.toggle() } } label: {
                    HStack(alignment: .top, spacing: 10) {
                    Image(systemName: location.status.isIssue ? "exclamationmark.triangle.fill" : "folder.fill")
                        .foregroundStyle(location.status.isIssue ? theme.warning : theme.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(location.name).font(.callout.weight(.semibold)).foregroundStyle(theme.primaryText)
                            if showsScope {
                                Text(location.scope.displayName).font(.caption2.weight(.medium)).foregroundStyle(theme.secondaryText)
                            }
                            if location.status != .measured {
                                Text(location.status.displayName).font(.caption2.weight(.semibold)).foregroundStyle(theme.warning)
                            }
                        }
                        Text(location.url.path).font(.caption2.monospaced()).foregroundStyle(theme.tertiaryText).lineLimit(1)
                        HStack(spacing: 8) {
                            Label(location.kind.displayName, systemImage: location.kind.systemImage)
                            if location.hasSharedBytes {
                                Text("\(StorageFormatters.bytes(location.referencedSize - location.uniqueSize)) shared elsewhere")
                            }
                        }
                        .font(.caption).foregroundStyle(theme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(StorageFormatters.bytes(location.uniqueSize))
                            .font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(theme.primaryText)
                        if expandable {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.bold)).foregroundStyle(theme.tertiaryText)
                        }
                    }
                    }
                    .padding(.leading, 11).padding(.vertical, 11).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(location.name), \(StorageFormatters.bytes(location.uniqueSize)), \(location.status.displayName)")
                .accessibilityHint(expandable ? "Expand to show the largest retained items" : "")
                Menu {
                    Button("Reveal in Finder") { actions.showInFinder(location.url) }
                    Button("Open in Terminal") { actions.openInTerminal(location.url) }
                    Button("Inspect Storage Map") { actions.inspectDirectory(location.url) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.top, 10).padding(.trailing, 9)
                .help("Location actions").accessibilityLabel("Actions for \(location.name)")
            }

            if isExpanded, let root = location.root {
                Divider().padding(.leading, 14)
                VStack(spacing: 0) {
                    ForEach(Array(root.sortedChildren.prefix(32))) { node in
                        HStack(spacing: 8) {
                            Image(systemName: node.isDirectory ? "folder" : "doc")
                                .foregroundStyle(theme.secondaryText).frame(width: 18)
                            Text(node.name).font(.caption).foregroundStyle(theme.primaryText).lineLimit(1)
                            Spacer()
                            Text(StorageFormatters.bytes(node.size))
                                .font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryText)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                    }
                }
            }
        }
        .background(theme.elevatedSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(theme.border.opacity(0.7)) }
    }

    private var expandable: Bool {
        location.root?.children.isEmpty == false
    }
}
