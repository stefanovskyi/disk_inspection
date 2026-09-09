import SwiftUI

struct ItemInspector: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsSmallItems = false
    @State private var selectedChildID: String?
    let node: FileNode

    private static let minimumVisibleFraction = 0.01

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let children = node.sortedChildren
        let prominentChildren = children.filter {
            $0.percentage(of: node.size) >= Self.minimumVisibleFraction
        }
        let smallItemCount = children.count - prominentChildren.count
        let visibleChildren = showsSmallItems ? children : prominentChildren
        let selectedChild = children.first { $0.id == selectedChildID }
        let inspectedNode = selectedChild ?? node

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(inspectedNode.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Text(inspectorSubtitle(for: inspectedNode, childCount: children.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    Spacer()
                    Text(StorageFormatters.bytes(inspectedNode.size))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                }

                HStack(spacing: 8) {
                    Button {
                        model.showInFinder(inspectedNode)
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    Button {
                        model.openInTerminal(inspectedNode)
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            if children.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: node.isReadable ? "tray" : "lock.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(node.isReadable ? theme.tertiaryText : theme.warning)
                    Text(node.isReadable ? "This folder is empty" : "This folder is protected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    if !node.isReadable {
                        Button("Open Full Disk Access Settings") {
                            model.openFullDiskAccessSettings()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(visibleChildren) { child in
                            InspectorRow(
                                node: child,
                                parentSize: node.size,
                                hue: SunburstLayout.hue(for: child.id),
                                isSelected: child.id == selectedChildID,
                                select: { selectedChildID = child.id }
                            )
                        }

                        if smallItemCount > 0 {
                            Button {
                                showsSmallItems.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showsSmallItems ? "chevron.up" : "chevron.down")
                                    Text(showsSmallItems ? "Show less" : "Show more")
                                    if !showsSmallItems {
                                        Text("(\(smallItemCount.formatted()))")
                                            .foregroundStyle(theme.tertiaryText)
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(showsSmallItems ? "Hide items smaller than 1%" : "Show items smaller than 1%")
                        }
                    }
                    .padding(8)
                }
            }
        }
        .onChange(of: node.id) {
            showsSmallItems = false
            selectedChildID = nil
        }
        .spacePanel()
    }

    private func inspectorSubtitle(for inspectedNode: FileNode, childCount: Int) -> String {
        if inspectedNode.id != node.id {
            return inspectedNode.isDirectory ? "Selected folder" : "Selected file"
        }
        return "\((node.directItemCount > 0 ? node.directItemCount : childCount).formatted()) direct items"
    }
}

struct SmallerItemsInspector: View {
    @Environment(\.colorScheme) private var colorScheme
    let selection: SunburstSmallerItems
    let dismiss: () -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selection.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text("in \(selection.parent.name) · \(selection.children.count.formatted()) entries")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Return to all items")
                    .accessibilityLabel("Close smaller items")
                }

                Text(StorageFormatters.bytes(selection.size))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            }
            .padding(16)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(selection.children) { child in
                        InspectorRow(
                            node: child,
                            parentSize: selection.size,
                            hue: SunburstLayout.hue(for: child.id)
                        )
                    }
                }
                .padding(8)
            }
        }
        .spacePanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Smaller items in \(selection.parent.name), \(StorageFormatters.bytes(selection.size))"
        )
    }
}

private struct InspectorRow: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let node: FileNode
    let parentSize: Int64
    let hue: Double
    var isSelected = false
    var select: (() -> Void)?

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let fraction = node.percentage(of: parentSize)
        let color = SpacePalette.color(hue: hue, depth: 0, isDark: colorScheme == .dark)

        Button {
            if let select {
                select()
            } else {
                activate()
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color.opacity(0.13))
                        Image(systemName: iconName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(node.isReadable ? color : theme.warning)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Text(StorageFormatters.percent(fraction))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                    }

                    Spacer(minLength: 6)

                    Text(StorageFormatters.bytes(node.size))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.secondaryText)

                    if node.isDirectory, !node.children.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.elevatedSurface)
                        Capsule()
                            .fill(color.opacity(0.82))
                            .frame(width: max(fraction > 0 ? 2 : 0, proxy.size.width * fraction))
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(isSelected || isHovered ? theme.elevatedSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { activate() }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if node.isAggregate {
                Button("Show Containing Folder in Finder") { model.showInFinder(node) }
                Button("Open Containing Folder in Terminal") { model.openInTerminal(node) }
            } else if node.isDirectory, !node.children.isEmpty {
                Button("Inspect “\(node.name)”") { model.navigate(into: node) }
                Divider()
                Button("Show in Finder") { model.showInFinder(node) }
                Button("Open in Terminal") { model.openInTerminal(node) }
            } else {
                Button("Show in Finder") { model.showInFinder(node) }
                Button("Open in Terminal") { model.openInTerminal(node) }
            }
        }
        .accessibilityLabel("\(node.name), \(StorageFormatters.bytes(node.size)), \(StorageFormatters.percent(fraction))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(
            select == nil
                ? activationHint
                : "Selects this item. Double-click to \(activationHint.lowercased())"
        )
    }

    private var activationHint: String {
        node.isDirectory && !node.children.isEmpty
            ? "Open this folder's storage map"
            : "Show this item in Finder"
    }

    private func activate() {
        if node.isAggregate {
            model.showInFinder(node)
        } else if node.isDirectory, !node.children.isEmpty {
            model.navigate(into: node)
        } else {
            model.showInFinder(node)
        }
    }

    private var iconName: String {
        if node.isAggregate { return "ellipsis.circle.fill" }
        if !node.isReadable { return "lock.fill" }
        if node.isDirectory { return "folder.fill" }
        return "doc.fill"
    }
}
