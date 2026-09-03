import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var smallerItemsSelection: SunburstSmallerItems?

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        HStack(spacing: 0) {
            VolumeSidebar()
                .frame(width: 264)

            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

            mainContent(theme: theme)
        }
        .background(theme.background)
        .overlay(alignment: .top) {
            if let message = model.errorMessage {
                ErrorBanner(message: message) {
                    model.errorMessage = nil
                }
                .padding(.top, 46)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if model.isRequestingFullDiskAccess {
                FullDiskAccessPrompt()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.errorMessage)
        .animation(.easeOut(duration: 0.2), value: model.isScanning)
        .animation(.easeOut(duration: 0.2), value: model.isRequestingFullDiskAccess)
    }

    @ViewBuilder
    private func mainContent(theme: SpaceTheme) -> some View {
        VStack(spacing: 0) {
            if let current = model.currentNode {
                NavigationHeader(node: current)

                if model.isScanning {
                    ScanProgressBar()
                        .padding(.horizontal, 14)
                        .padding(.bottom, 2)
                }

                HStack(spacing: 14) {
                    ChartPanel(
                        node: current,
                        volume: model.volumeForChart(node: current),
                        isProvisional: model.isScanning,
                        inspectSmallerItems: { smallerItemsSelection = $0 }
                    )
                        .frame(minWidth: 500)
                        .allowsHitTesting(!model.isScanning)

                    Group {
                        if let selection = smallerItemsSelection,
                           selection.chartRootID == current.id {
                            SmallerItemsInspector(selection: selection) {
                                smallerItemsSelection = nil
                            }
                        } else {
                            ItemInspector(node: current)
                        }
                    }
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)
                        .allowsHitTesting(!model.isScanning)
                }
                .padding(14)
                .padding(.top, -2)
            } else if let volume = model.selectedVolumeOverview {
                DiskOverview(
                    volume: volume,
                    previousSummary: model.previousScanSummary,
                    previousRoot: model.previousScanRoot
                )
            } else {
                WelcomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .onChange(of: model.currentNode?.id) {
            smallerItemsSelection = nil
        }
        .onChange(of: model.isScanning) {
            if model.isScanning {
                smallerItemsSelection = nil
            }
        }
    }
}

private struct FullDiskAccessPrompt: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.5 : 0.24)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("Full Disk Access recommended")
                        .font(.system(size: 20, weight: .semibold))

                    Text(
                        "For a complete storage map, enable SpaceLens in System Settings. "
                            + "Without Full Disk Access, macOS will hide protected folders and the totals will be incomplete."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("SpaceLens only reads file sizes. It never modifies your files.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 9) {
                    Button {
                        model.openFullDiskAccessSettings()
                    } label: {
                        Label("Open Full Disk Access Settings", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .foregroundStyle(Color.black.opacity(0.82))

                    Text("After enabling SpaceLens, return here and access will be checked again. macOS may ask you to reopen the app.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            model.cancelPendingDiskScan()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("Scan with Current Access") {
                            model.scanPendingDiskWithCurrentAccess()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(width: 470)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 26, y: 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full Disk Access recommended before scanning")
    }
}

private struct ErrorBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    let dismiss: () -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 620)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.warning.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .padding(.horizontal, 20)
    }
}

private struct ScanProgressBar: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Label("Mapping storage", systemImage: "externaldrive.badge.timemachine")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                if let fraction = model.estimatedScanFraction {
                    Text("~\(Int((fraction * 100).rounded(.down)))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.accent)
                        .help("Estimated from mapped bytes; filesystem scans cannot know all remaining work in advance")
                } else {
                    Text("Estimating…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer(minLength: 10)

                Text("\(StorageFormatters.bytes(model.progress.mappedBytes)) mapped")
                Text("\(model.progress.itemsScanned.formatted()) items")

                if let startedAt = model.scanStartedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                        Label(
                            StorageFormatters.duration(
                                max(timeline.date.timeIntervalSince(startedAt), 0)
                            ),
                            systemImage: "clock"
                        )
                    }
                }

                if model.progress.unresponsiveItems > 0 {
                    Label(
                        "\(model.progress.unresponsiveItems) skipped",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(theme.warning)
                }

                Button("Cancel") { model.cancelScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }

            Group {
                if let fraction = model.estimatedScanFraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(theme.accent)

            Text(model.progress.currentPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanning in progress")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let estimate = model.estimatedScanFraction.map {
            "estimated \(Int(($0 * 100).rounded(.down))) percent, "
        } ?? ""
        return "\(estimate)\(model.progress.itemsScanned.formatted()) items, \(StorageFormatters.bytes(model.progress.mappedBytes)) mapped"
    }
}
