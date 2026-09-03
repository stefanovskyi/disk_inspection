import SwiftUI

struct DiskOverview: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    let volume: VolumeInfo
    let previousSummary: PreviousScanSummary?
    let previousRoot: FileNode?

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            header(theme: theme)

            HStack(spacing: 14) {
                mapPanel(theme: theme)
                    .frame(minWidth: 500)

                detailsPanel(theme: theme)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)
            }
            .padding(14)
            .padding(.top, -2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(theme: SpaceTheme) -> some View {
        HStack(spacing: 12) {
            Image(systemName: volume.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("Capacity overview")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
            }

            Spacer(minLength: 12)

            if previousSummary != nil {
                Label("Previous scan", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(theme.elevatedSurface)
                    .clipShape(Capsule())
            }

            Button {
                model.scan(volume.url)
            } label: {
                Label(previousSummary == nil ? "Scan Disk" : "Update Scan", systemImage: "viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .foregroundStyle(Color.black.opacity(0.82))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 35)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func mapPanel(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(previousRoot == nil ? "Disk capacity" : "Last known storage map")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(mapSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Group {
                if let previousRoot {
                    SunburstChart(root: previousRoot, volume: volume, isProvisional: false)
                } else {
                    CapacityShellChart(volume: volume)
                }
            }
            .allowsHitTesting(false)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Label(
                previousRoot == nil
                    ? "Folder sizes appear as soon as the scan starts"
                    : "Start an update to replace this snapshot with live results",
                systemImage: previousRoot == nil ? "sparkles" : "arrow.triangle.2.circlepath"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .spacePanel()
    }

    private var mapSubtitle: String {
        guard let previousSummary else {
            return "Available instantly from macOS — no folder scan required"
        }
        return "Historical folder sizes from \(previousSummary.scannedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func detailsPanel(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage now")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("Read directly from the mounted volume")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
            }

            VStack(spacing: 12) {
                capacityRow("Total capacity", value: volume.totalCapacity, theme: theme)
                capacityRow("Used", value: volume.usedCapacity, theme: theme)
                capacityRow("Available", value: volume.availableCapacity, theme: theme)
            }

            Divider().overlay(theme.border)

            VStack(spacing: 11) {
                detailRow("Format", value: volume.fileSystemType ?? "Unknown", theme: theme)
                detailRow("Location", value: volume.isExternal ? "External" : "This Mac", theme: theme)
                detailRow("Access", value: volume.isReadOnly ? "Read only" : "Readable", theme: theme)
                if let isEncrypted = volume.isEncrypted {
                    detailRow("Encryption", value: isEncrypted ? "Encrypted" : "Not encrypted", theme: theme)
                }
            }

            if let previousSummary {
                Divider().overlay(theme.border)

                VStack(alignment: .leading, spacing: 7) {
                    Label("Previous scan snapshot", systemImage: "clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    Text(
                        "\(previousSummary.itemsScanned.formatted()) items in "
                            + StorageFormatters.duration(previousSummary.duration)
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    if previousSummary.unreadableItems > 0 {
                        Label(
                            "\(previousSummary.unreadableItems.formatted()) protected items were not measured",
                            systemImage: "lock.fill"
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.warning)
                    }
                }
            }

            Spacer(minLength: 0)

            Text("Capacity is current. Folder sizes require a scan and may differ from the used total because macOS can restrict access to protected data.")
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .spacePanel()
    }

    private func capacityRow(_ label: String, value: Int64, theme: SpaceTheme) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Text(StorageFormatters.bytes(value))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(theme.primaryText)
        }
    }

    private func detailRow(_ label: String, value: String, theme: SpaceTheme) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(theme.tertiaryText)
            Spacer()
            Text(value)
                .foregroundStyle(theme.secondaryText)
        }
        .font(.system(size: 11, weight: .medium))
    }
}

private struct CapacityShellChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let volume: VolumeInfo

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = diameter * 0.35
            let lineWidth = max(28, diameter * 0.15)
            let usedEnd = Angle.degrees(-90 + (360 * volume.usedFraction))

            ZStack {
                Canvas { context, _ in
                    var freeArc = Path()
                    freeArc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270),
                        clockwise: false
                    )
                    context.stroke(
                        freeArc,
                        with: .color(theme.elevatedSurface),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )

                    if volume.usedFraction > 0 {
                        var usedArc = Path()
                        usedArc.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .degrees(-90),
                            endAngle: usedEnd,
                            clockwise: false
                        )
                        context.stroke(
                            usedArc,
                            with: .color(theme.secondaryText.opacity(0.42)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                        )
                    }
                }

                VStack(spacing: 4) {
                    Text(StorageFormatters.bytes(volume.usedCapacity))
                        .font(.system(size: min(27, diameter * 0.06), weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("used of \(StorageFormatters.bytes(volume.totalCapacity))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
                .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(volume.name), \(StorageFormatters.bytes(volume.usedCapacity)) used, "
                + "\(StorageFormatters.bytes(volume.availableCapacity)) available"
        )
    }
}
