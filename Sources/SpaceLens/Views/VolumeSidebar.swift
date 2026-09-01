import SwiftUI

struct VolumeSidebar: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var internalVolumes: [VolumeInfo] { model.volumes.filter { !$0.isExternal } }
    private var externalVolumes: [VolumeInfo] { model.volumes.filter(\.isExternal) }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            brand(theme: theme)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    volumeSection("This Mac", volumes: internalVolumes, theme: theme)

                    if !externalVolumes.isEmpty {
                        volumeSection("External", volumes: externalVolumes, theme: theme)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }

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
                .foregroundStyle(Color.black.opacity(0.8))

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
            .background(theme.surface.opacity(0.72))
        }
        .background(theme.sidebar)
    }

    private func brand(theme: SpaceTheme) -> some View {
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
        .padding(.top, 38)
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func volumeSection(_ title: String, volumes: [VolumeInfo], theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(theme.tertiaryText)
                .padding(.horizontal, 8)

            if volumes.isEmpty {
                Text(title == "External" ? "No external disks mounted" : "No disks found")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            } else {
                ForEach(volumes) { volume in
                    VolumeRow(
                        volume: volume,
                        isActive: model.result?.root.url.standardizedFileURL == volume.url.standardizedFileURL
                            || model.scanningURL?.standardizedFileURL == volume.url.standardizedFileURL
                    )
                }
            }
        }
    }
}

private struct VolumeRow: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    let volume: VolumeInfo
    let isActive: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        Button {
            model.scan(volume.url)
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

                        Text("\(StorageFormatters.bytes(volume.usedCapacity)) of \(StorageFormatters.bytes(volume.totalCapacity))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if model.scanningURL?.standardizedFileURL == volume.url.standardizedFileURL {
                        ProgressView()
                            .controlSize(.small)
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
            Button("Scan") { model.scan(volume.url) }
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
        .accessibilityLabel("\(volume.name), \(StorageFormatters.percent(volume.usedFraction)) used")
        .accessibilityHint("Scans this disk")
    }
}
