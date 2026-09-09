import SwiftUI

struct VolumeSidebar: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("layout.sidebarWidth") private var sidebarWidth = 248.0

    private var internalVolumes: [VolumeInfo] { model.volumes.filter { !$0.isExternal } }
    private var externalVolumes: [VolumeInfo] { model.volumes.filter(\.isExternal) }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            brand(theme: theme)

            List(selection: sidebarSelection) {
                volumeSection("This Mac", volumes: internalVolumes, theme: theme)

                if !externalVolumes.isEmpty {
                    volumeSection("External", volumes: externalVolumes, theme: theme)
                }

                if !model.sessionFolders.isEmpty {
                    sessionFolderSection(theme: theme)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onDeleteCommand(perform: removeSelectedFolder)

            Spacer(minLength: 0)

            VStack(spacing: 9) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Scan a Folder", systemImage: "folder.badge.plus")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)

                Button {
                    model.refreshVolumes()
                } label: {
                    Label("Refresh Disks", systemImage: "arrow.clockwise")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)
                .accessibilityHint("Refreshes the list of mounted disks")
            }
            .padding(14)
            .background(.bar)
        }
        .background(theme.sidebar)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { persistSidebarWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) {
                        persistSidebarWidth(proxy.size.width)
                    }
            }
        }
    }

    private func brand(theme: SpaceTheme) -> some View {
        Button {
            model.showDiskList()
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(theme.elevatedSurface)
                    Circle()
                        .trim(from: 0.04, to: 0.78)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(5)
                    Circle()
                        .trim(from: 0.16, to: 0.56)
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(10)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SpaceLens")
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(theme.primaryText)
                    Text("Storage inspector")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.tertiaryText)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.top, 12)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Back to disks")
        .accessibilityLabel("SpaceLens home")
        .accessibilityHint("Returns to the list of disks")
    }

    @ViewBuilder
    private func volumeSection(_ title: String, volumes: [VolumeInfo], theme: SpaceTheme) -> some View {
        Section(title) {
            if volumes.isEmpty {
                Text(title == "External" ? "No external disks mounted" : "No disks found")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.vertical, 10)
            } else {
                ForEach(volumes) { volume in
                    VolumeRow(
                        volume: volume,
                        showsLocation: volumes.filter { $0.name == volume.name }.count > 1
                    )
                    .tag(SidebarSelection.volume(volume.url.standardizedFileURL.path))
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    private func sessionFolderSection(theme: SpaceTheme) -> some View {
        Section("Folders") {
            ForEach(model.sessionFolders) { folder in
                SessionFolderRow(folder: folder)
                    .tag(SidebarSelection.folder(folder.id))
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                guard let path = activeLocationPath else { return nil }
                if model.sessionFolders.contains(where: { $0.id == path }) {
                    return .folder(path)
                }
                if model.volumes.contains(where: {
                    $0.url.standardizedFileURL.path == path
                }) {
                    return .volume(path)
                }
                return nil
            },
            set: { selection in
                switch selection {
                case .volume(let path):
                    if let volume = model.volumes.first(where: {
                        $0.url.standardizedFileURL.path == path
                    }) {
                        model.selectVolume(volume)
                    }
                case .folder(let path):
                    if let folder = model.sessionFolders.first(where: { $0.id == path }) {
                        model.selectSessionFolder(folder)
                    }
                case nil:
                    break
                }
            }
        )
    }

    private var activeLocationPath: String? {
        model.scanningURL?.standardizedFileURL.path
            ?? model.result?.root.url.standardizedFileURL.path
            ?? model.selectedVolumeOverview?.url.standardizedFileURL.path
    }

    private func removeSelectedFolder() {
        guard case .folder(let path) = sidebarSelection.wrappedValue,
              let folder = model.sessionFolders.first(where: { $0.id == path }) else { return }
        model.removeSessionFolder(folder)
    }

    private func persistSidebarWidth(_ width: CGFloat) {
        let width = Double(width)
        guard width >= 220, width <= 320, abs(sidebarWidth - width) >= 1 else { return }
        sidebarWidth = width
    }
}

private enum SidebarSelection: Hashable {
    case volume(String)
    case folder(String)
}

private struct VolumeRow: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let volume: VolumeInfo
    let showsLocation: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let hasCachedResult = model.cachedResult(for: volume) != nil

        VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: volume.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(volumeSubtitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if model.scanningURL?.standardizedFileURL == volume.url.standardizedFileURL {
                        ProgressView()
                            .controlSize(.small)
                    } else if hasCachedResult {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.elevatedSurface)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [theme.accent, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(3, proxy.size.width * volume.usedFraction))
                    }
                }
                .frame(height: 4)
            }
            .padding(11)
            .contentShape(Rectangle())
        .contextMenu {
            if hasCachedResult {
                Button("View Existing Result") { model.viewCachedResult(at: volume.url) }
                Button("Rescan Disk") { model.scan(volume.url) }
                Divider()
            } else {
                Button("Scan") { model.scan(volume.url) }
                Divider()
            }
            Button("Show in Finder") {
                let node = FileNode(
                    url: volume.url,
                    name: volume.name,
                    size: volume.usedCapacity,
                    isDirectory: true,
                    isReadable: true,
                    children: []
                )
                model.showInFinder(node)
            }
        }
        .accessibilityLabel(
            "\(volume.name), \(StorageFormatters.percent(volume.usedFraction)) used"
                + (showsLocation ? ", mounted at \(volume.url.path)" : "")
                + (hasCachedResult ? ", session scan available" : "")
        )
        .accessibilityHint(hasCachedResult ? "Opens the saved scan immediately" : "Shows this disk overview")
    }

    private var volumeSubtitle: String {
        let capacity = "\(StorageFormatters.bytes(volume.usedCapacity)) of \(StorageFormatters.bytes(volume.totalCapacity))"
        return showsLocation ? "\(capacity) · \(volume.url.path)" : capacity
    }
}

private struct SessionFolderRow: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let folder: SessionFolder

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let cachedResult = model.cachedResult(for: folder)
        let isScanning = model.scanningURL?.standardizedFileURL.path == folder.id

        HStack(spacing: 3) {
            HStack(spacing: 9) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(
                            cachedResult.map {
                                "\(StorageFormatters.bytes($0.root.size)) scanned"
                            } ?? folder.url.deletingLastPathComponent().path
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else if cachedResult != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                .padding(.leading, 9)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            .frame(maxWidth: .infinity)

            Button {
                model.removeSessionFolder(folder)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(folder.name) from sidebar")
            .accessibilityLabel("Remove \(folder.name) from sidebar")
            .padding(.trailing, 4)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if cachedResult != nil {
                Button("View Existing Result") { model.viewCachedResult(at: folder.url) }
                Button("Rescan Folder") { model.scan(folder.url) }
            } else {
                Button("Scan Folder") { model.scan(folder.url) }
            }
            Divider()
            Button("Show in Finder") {
                model.showInFinder(
                    FileNode(
                        url: folder.url,
                        name: folder.name,
                        size: cachedResult?.root.size ?? 0,
                        isDirectory: true,
                        isReadable: true,
                        children: []
                    )
                )
            }
            Button("Remove from Sidebar") {
                model.removeSessionFolder(folder)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
