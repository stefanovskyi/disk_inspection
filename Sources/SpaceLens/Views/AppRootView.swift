import SwiftUI

struct AppRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var smallerItemsSelection: SunburstSmallerItems?

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        NavigationSplitView {
            VolumeSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        } detail: {
            mainContent(theme: theme)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            model.navigateBack()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(!model.canNavigateBack)
                        .help("Go back (⌘[)")
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        if model.isScanning {
                            ScanToolbarStatus()

                            Button {
                                model.cancelScan()
                            } label: {
                                Label("Cancel Scan", systemImage: "xmark.circle")
                            }
                            .help("Cancel the current scan")
                        } else if model.result != nil {
                            Button {
                                model.rescan()
                            } label: {
                                Label("Rescan", systemImage: "arrow.clockwise")
                            }
                            .help("Scan this location again (⌘R)")
                        }

                        Button {
                            model.chooseFolder()
                        } label: {
                            Label("Scan Folder", systemImage: "folder.badge.plus")
                        }
                        .help("Choose a folder to scan (⌘O)")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .background(theme.background)
        .overlay(alignment: .top) {
            if let message = model.errorMessage {
                ErrorBanner(message: message) {
                    model.errorMessage = nil
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.isRequestingFullDiskAccess },
                set: { isPresented in
                    if !isPresented { model.cancelPendingDiskScan() }
                }
            )
        ) {
            FullDiskAccessPrompt()
        }
        .animation(.easeOut(duration: 0.16), value: model.errorMessage)
    }

    @ViewBuilder
    private func resultContent(current: FileNode) -> some View {
        HSplitView {
            ChartPanel(
                node: current,
                volume: model.volumeForChart(node: current),
                isProvisional: model.isScanning && model.result == nil,
                inspectSmallerItems: { smallerItemsSelection = $0 }
            )
            .frame(minWidth: 500)
            .allowsHitTesting(!model.isScanning || model.result != nil)

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
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
            .allowsHitTesting(!model.isScanning || model.result != nil)
        }
        .padding(12)
    }

    @ViewBuilder
    private func mainContent(theme: SpaceTheme) -> some View {
        VStack(spacing: 0) {
            if let current = model.currentNode {
                NavigationHeader(node: current)
                resultContent(current: current)
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
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

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
        .background(theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full Disk Access recommended before scanning")
    }
}

private struct ScanToolbarStatus: View {
    @Environment(AppViewModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let fraction = model.estimatedScanFraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .controlSize(.small)
            .frame(width: 72)

            Text("\(model.progress.itemsScanned.formatted()) items")
                .font(.caption)
                .monospacedDigit()
        }
        .help(
            "\(StorageFormatters.bytes(model.progress.mappedBytes)) mapped\n"
                + model.progress.currentPath
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanning in progress")
        .accessibilityValue(
            "\(model.progress.itemsScanned.formatted()) items, "
                + "\(StorageFormatters.bytes(model.progress.mappedBytes)) mapped"
        )
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
