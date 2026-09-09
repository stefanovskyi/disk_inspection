import SwiftUI

struct ItemInspector: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsSmallItems = false
    let node: FileNode
    @Binding var selectedItem: FileNode?

    private static let minimumVisibleFraction = 0.01

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let children = node.sortedChildren
        let prominentChildren = children.filter {
            $0.percentage(of: node.size) >= Self.minimumVisibleFraction
        }
        let smallItemCount = children.count - prominentChildren.count
        let visibleChildren = showsSmallItems ? children : prominentChildren
        let inspectedNode = selectedItem ?? node

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(inspectedNode.name)
                            .font(.headline)
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Text(inspectorSubtitle(for: inspectedNode, childCount: children.count))
                            .font(.caption)
                            .foregroundStyle(theme.tertiaryText)
                    }
                    Spacer()
                    Text(StorageFormatters.bytes(inspectedNode.size))
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
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
                .font(.caption2.weight(.semibold))
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
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                    if !node.isReadable {
                        Button("Open Full Disk Access Settings") {
                            model.openFullDiskAccessSettings()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: directSelection(in: children)) {
                    ForEach(visibleChildren) { child in
                        InspectorRow(
                            node: child,
                            parentSize: node.size,
                            hue: SunburstLayout.hue(for: child.id),
                            select: { selectedItem = child }
                        )
                        .tag(child.id)
                        .listRowSeparator(.hidden)
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
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(showsSmallItems ? "Hide items smaller than 1%" : "Show items smaller than 1%")
                    }
                }
                .listStyle(.inset)
                .focusable()
                .onKeyPress(.return) { activateSelection() }
            }
        }
        .onChange(of: node.id) {
            showsSmallItems = false
            selectedItem = nil
        }
        .spacePanel()
    }

    private func inspectorSubtitle(for inspectedNode: FileNode, childCount: Int) -> String {
        if inspectedNode.id != node.id {
            return inspectedNode.isDirectory ? "Selected folder" : "Selected file"
        }
        return "\((node.directItemCount > 0 ? node.directItemCount : childCount).formatted()) direct items"
    }

    private func directSelection(in children: [FileNode]) -> Binding<String?> {
        Binding(
            get: {
                guard let selectedItem else { return nil }
                if children.contains(where: { $0.id == selectedItem.id }) {
                    return selectedItem.id
                }
                let selectedPath = selectedItem.url.standardizedFileURL.path
                return children.first(where: { child in
                    let childPath = child.url.standardizedFileURL.path
                    return selectedPath.hasPrefix(childPath + "/")
                })?.id
            },
            set: { id in
                selectedItem = id.flatMap { id in
                    children.first { $0.id == id }
                }
            }
        )
    }

    private func activateSelection() -> KeyPress.Result {
        guard let selectedItem else { return .ignored }
        activate(selectedItem)
        return .handled
    }

    private func activate(_ item: FileNode) {
        if item.isAggregate {
            model.showInFinder(item)
        } else if item.isDirectory, !item.children.isEmpty {
            model.navigate(into: item)
        } else {
            model.showInFinder(item)
        }
    }
}

struct SmallerItemsInspector: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let selection: SunburstSmallerItems
    @Binding var selectedItem: FileNode?
    let dismiss: () -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        let inspectedItem = selectedItem

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(inspectedItem?.name ?? selection.name)
                            .font(.headline)
                            .foregroundStyle(theme.primaryText)
                        Text(
                            inspectedItem == nil
                                ? "in \(selection.parent.name) · \(selection.children.count.formatted()) entries"
                                : (inspectedItem?.isDirectory == true ? "Selected folder" : "Selected file")
                        )
                            .font(.caption)
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

                Text(StorageFormatters.bytes(inspectedItem?.size ?? selection.size))
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
            }
            .padding(16)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)

            List(selection: smallerItemsSelection) {
                ForEach(selection.children) { child in
                    InspectorRow(
                        node: child,
                        parentSize: selection.size,
                        hue: SunburstLayout.hue(for: child.id),
                        select: { selectedItem = child }
                    )
                    .tag(child.id)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .focusable()
            .onKeyPress(.return) { activateSelection() }
        }
        .spacePanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Smaller items in \(selection.parent.name), \(StorageFormatters.bytes(selection.size))"
        )
    }

    private var smallerItemsSelection: Binding<String?> {
        Binding(
            get: { selectedItem?.id },
            set: { id in
                selectedItem = id.flatMap { id in
                    selection.children.first { $0.id == id }
                }
            }
        )
    }

    private func activateSelection() -> KeyPress.Result {
        guard let selectedItem else { return .ignored }
        if selectedItem.isAggregate {
            model.showInFinder(selectedItem)
        } else if selectedItem.isDirectory, !selectedItem.children.isEmpty {
            model.navigate(into: selectedItem)
        } else {
            model.showInFinder(selectedItem)
        }
        return .handled
    }
}

private struct InspectorRow: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let node: FileNode
    let parentSize: Int64
    let hue: Double
    let select: () -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let fraction = node.percentage(of: parentSize)
        let color = SpacePalette.color(hue: hue, depth: 0, isDark: colorScheme == .dark)

        VStack(spacing: 8) {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color.opacity(0.13))
                        Image(systemName: iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(node.isReadable ? color : theme.warning)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Text(StorageFormatters.percent(fraction))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.tertiaryText)
                    }

                    Spacer(minLength: 6)

                    Text(StorageFormatters.bytes(node.size))
                        .font(.caption.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)

                    if node.isDirectory, !node.children.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
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
        .background(isHovered ? theme.elevatedSurface.opacity(0.55) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded(performPrimaryAction)
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
        .accessibilityHint(primaryActionHint)
        .accessibilityAction(named: "Open", activate)
    }

    private var activationHint: String {
        node.isDirectory && !node.children.isEmpty
            ? "Open this folder's storage map"
            : "Show this item in Finder"
    }

    private var primaryActionHint: String {
        node.isDirectory && !node.children.isEmpty
            ? activationHint
            : "Selects this item"
    }

    private func performPrimaryAction() {
        if node.isDirectory, !node.children.isEmpty {
            activate()
        } else {
            select()
        }
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
