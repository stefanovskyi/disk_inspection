import SwiftUI

struct VolumeSidebar: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var internalVolumes: [VolumeInfo] { model.volumes.filter { !$0.isExternal } }
    private var externalVolumes: [VolumeInfo] { model.volumes.filter(\.isExternal) }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            brand(theme: theme)

            List {
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

            Spacer(minLength: 0)

            VStack(spacing: 9) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Scan a Folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)

                Button {
                    model.refreshVolumes()
                } label: {
                    Label("Refresh Disks", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)
                .accessibilityHint("Refreshes the list of mounted disks")
            }
            .padding(14)
            .background(.bar)
        }
        .background(theme.sidebar)
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
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("Storage inspector")
                        .font(.system(size: 10, weight: .medium))
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
                        showsLocation: volumes.filter { $0.name == volume.name }.count > 1,
                        isActive: model.result?.root.url.standardizedFileURL == volume.url.standardizedFileURL
                            || model.scanningURL?.standardizedFileURL == volume.url.standardizedFileURL
                            || model.selectedVolumeOverview?.url.standardizedFileURL == volume.url.standardizedFileURL
                    )
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
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }
}

private struct VolumeRow: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let volume: VolumeInfo
    let showsLocation: Bool
    let isActive: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let hasCachedResult = model.cachedResult(for: volume) != nil

        Button {
            model.selectVolume(volume)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: volume.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isActive ? theme.accent : theme.secondaryText)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(volumeSubtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if model.scanningURL?.standardizedFileURL == volume.url.standardizedFileURL {
                        ProgressView()
                            .controlSize(.small)
                    } else if hasCachedResult {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
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
            .background(isActive ? theme.elevatedSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        let isActive = model.result?.root.url.standardizedFileURL.path == folder.id || isScanning

        HStack(spacing: 3) {
            Button {
                model.selectSessionFolder(folder)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isActive ? theme.accent : theme.secondaryText)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(
                            cachedResult.map {
                                "\(StorageFormatters.bytes($0.root.size)) scanned"
                            } ?? folder.url.deletingLastPathComponent().path
                        )
                        .font(.system(size: 10, weight: .medium))
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                .padding(.leading, 9)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
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

            Button {
                model.removeSessionFolder(folder)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(folder.name) from sidebar")
            .accessibilityLabel("Remove \(folder.name) from sidebar")
            .padding(.trailing, 4)
        }
        .background(isActive ? theme.elevatedSurface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
