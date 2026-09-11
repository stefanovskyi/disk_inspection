import SwiftUI

private struct AICodingOutlineRow<Content: View, Actions: View>: View {
    let expansion: Binding<Bool>?
    let accessibilityLabel: String
    let padding: EdgeInsets
    let actionsAlignment: Alignment
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Group {
            if let expansion {
                Button {
                    expansion.wrappedValue.toggle()
                } label: {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(expansion.wrappedValue ? "Expanded" : "Collapsed")
                .accessibilityHint(expansion.wrappedValue ? "Collapse this folder" : "Expand to show folders and files")
            } else {
                rowContent
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel)
            }
        }
        .overlay(alignment: actionsAlignment) {
            // Keep the menu separate from the expansion button so opening it never toggles the row.
            actions()
                .padding(padding)
        }
    }

    private var rowContent: some View {
        content()
            .padding(.trailing, 28)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct AICodingLocationOutline: View {
    @Environment(\.colorScheme) private var colorScheme
    let location: AICodingStorageLocation
    @Binding var expandedNodeIDs: Set<String>
    let actions: AICodingToolsViewActions

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            AICodingOutlineRow(
                expansion: expandableRoot.map { expansionBinding(for: $0.id) },
                accessibilityLabel: locationAccessibilityLabel,
                padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
                actionsAlignment: .topTrailing
            ) {
                locationHeader(theme: theme)
            } actions: {
                locationMenu
            }
            .accessibilityAction(named: "Show in Finder") {
                if canOpen { actions.showInFinder(location.url) }
            }
            .accessibilityAction(named: "Open in Terminal") {
                if canOpen { actions.openInTerminal(location.url) }
            }
            .accessibilityAction(named: "Inspect Storage Map") {
                if let root = location.root, root.isDirectory, root.isReadable {
                    actions.inspect(root)
                }
            }

            if let root = expandableRoot, expandedNodeIDs.contains(root.id) {
                VStack(spacing: 0) {
                    Divider()
                    ForEach(root.sortedChildren) { child in
                        AICodingFilesystemNodeRow(
                            node: child,
                            location: location,
                            rootSize: max(location.size, 1),
                            expandedNodeIDs: $expandedNodeIDs,
                            actions: actions
                        )
                        if child.id != root.sortedChildren.last?.id {
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
        }
        .spacePanel()
    }

    private var expandableRoot: FileNode? {
        guard let root = location.root, root.isDirectory, !root.children.isEmpty else { return nil }
        return root
    }

    private func locationHeader(theme: SpaceTheme) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusImage(location.status))
                .foregroundStyle(location.status.isIssue ? theme.warning : theme.accent)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(location.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    if location.status != .measured {
                        Text(location.status.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(location.status.isIssue ? theme.warning : theme.tertiaryText)
                    }
                }
                Text(location.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                Text(location.explanation)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(StorageFormatters.bytes(location.size))
                    .font(.callout.weight(.semibold).monospacedDigit())
                Text("\(location.itemCount.formatted()) items")
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
                if let date = location.latestModificationDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .foregroundStyle(theme.primaryText)
        }
    }

    private var locationMenu: some View {
        Menu {
            Button {
                actions.showInFinder(location.url)
            } label: {
                Label("Show in Finder", systemImage: "finder")
            }
            Button {
                actions.openInTerminal(location.url)
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
            if let root = location.root, root.isDirectory, root.isReadable {
                Button {
                    actions.inspect(root)
                } label: {
                    Label("Inspect Storage Map", systemImage: "chart.pie")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 18, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!canOpen)
        .help("Location actions")
        .accessibilityLabel("Actions for \(location.name)")
    }

    private var canOpen: Bool {
        location.status == .measured
            || location.status == .unreadable
            || location.status == .stalled
    }

    private var locationAccessibilityLabel: String {
        "\(location.name), \(StorageFormatters.bytes(location.size)), "
            + "\(location.itemCount.formatted()) items, \(location.status.displayName), "
            + "\(location.explanation)"
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedNodeIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedNodeIDs.insert(id)
                } else {
                    expandedNodeIDs.remove(id)
                }
            }
        )
    }
}

struct AICodingFilesystemNodeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let node: FileNode
    let location: AICodingStorageLocation
    let rootSize: Int64
    @Binding var expandedNodeIDs: Set<String>
    let actions: AICodingToolsViewActions

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            AICodingOutlineRow(
                expansion: canExpand ? expansionBinding : nil,
                accessibilityLabel: nodeAccessibilityLabel,
                padding: EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0),
                actionsAlignment: .trailing
            ) {
                nodeContent(theme: theme)
            } actions: {
                nodeMenu
            }

            if canExpand, expandedNodeIDs.contains(node.id) {
                VStack(spacing: 0) {
                    ForEach(node.sortedChildren) { child in
                        AICodingFilesystemNodeRow(
                            node: child,
                            location: location,
                            rootSize: rootSize,
                            expandedNodeIDs: $expandedNodeIDs,
                            actions: actions
                        )
                        if child.id != node.sortedChildren.last?.id {
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
        .contextMenu {
            if !node.isAggregate {
                Button("Show in Finder") { actions.showInFinder(node.url) }
                Button("Open in Terminal") { actions.openInTerminal(terminalURL(for: node)) }
                if node.isDirectory, node.isReadable {
                    Button("Inspect Storage Map") { actions.inspect(node) }
                }
            }
        }
    }

    private func nodeContent(theme: SpaceTheme) -> some View {
        let annotation = location.annotation(for: node)

        return HStack(alignment: .center, spacing: 9) {
            Image(systemName: nodeImage)
                .foregroundStyle(node.isReadable ? theme.accent : theme.warning)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(annotation.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    if let category = annotation.visibleCategory {
                        Label(category.displayName, systemImage: category.systemImage)
                            .labelStyle(.titleOnly)
                            .font(.caption2)
                            .foregroundStyle(categoryColor(category, colorScheme: colorScheme))
                            .lineLimit(1)
                    }
                }
                if let explanation = annotation.visibleExplanation {
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(StorageFormatters.bytes(node.size))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.primaryText)
                Text(nodeMetadata)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .help(node.isAggregate ? annotation.explanation : node.url.path)
    }

    @ViewBuilder
    private var nodeMenu: some View {
        if !node.isAggregate {
            Menu {
                Button("Show in Finder") { actions.showInFinder(node.url) }
                Button("Open in Terminal") { actions.openInTerminal(terminalURL(for: node)) }
                if node.isDirectory, node.isReadable {
                    Button("Inspect Storage Map") { actions.inspect(node) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Actions for \(nodeDisplayName)")
            .accessibilityLabel("Actions for \(nodeDisplayName)")
        }
    }

    private var canExpand: Bool {
        node.isDirectory && !node.children.isEmpty && !node.isAggregate
    }

    private var nodeAccessibilityLabel: String {
        let annotation = location.annotation(for: node)
        var parts = [
            annotation.displayName,
            node.isDirectory ? "folder" : "file",
            StorageFormatters.bytes(node.size),
            annotation.category.displayName
        ]
        if annotation.isComponentRoot {
            parts.append(annotation.explanation)
        }
        return parts.joined(separator: ", ")
    }

    private var nodeDisplayName: String {
        location.annotation(for: node).displayName
    }

    private var nodeMetadata: String {
        let percent = StorageFormatters.percent(node.percentage(of: rootSize))
        if node.isDirectory || node.isAggregate {
            return "\(percent) · \(node.itemCount.formatted()) items"
        }
        return percent
    }

    private func terminalURL(for node: FileNode) -> URL {
        node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    private var nodeImage: String {
        if node.isAggregate { return "square.stack.3d.up.fill" }
        if !node.isReadable { return "lock.fill" }
        return node.isDirectory ? "folder.fill" : "doc.fill"
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedNodeIDs.contains(node.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedNodeIDs.insert(node.id)
                } else {
                    expandedNodeIDs.remove(node.id)
                }
            }
        )
    }
}

func categoryColor(
    _ category: AICodingStorageCategory,
    colorScheme: ColorScheme
) -> Color {
    let index = AICodingStorageCategory.allCases.firstIndex(of: category) ?? 0
    return SpacePalette.color(
        hue: SpacePalette.hues[index % SpacePalette.hues.count],
        depth: 1,
        isDark: colorScheme == .dark
    )
}

func statusImage(_ status: AICodingLocationStatus) -> String {
    switch status {
    case .measured: "checkmark.circle.fill"
    case .missing: "minus.circle"
    case .unreadable: "lock.fill"
    case .stalled: "clock.fill"
    case .linked: "link"
    case .notDiscoverable: "questionmark.circle"
    }
}
