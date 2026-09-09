import SwiftUI

struct AppRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("layout.sidebarVisible") private var isSidebarVisible = true
    @AppStorage("layout.sidebarWidth") private var sidebarWidth = 248.0
    @AppStorage("layout.inspectorVisible") private var isInspectorVisible = true
    @AppStorage("layout.inspectorWidth") private var inspectorWidth = 340.0
    @State private var smallerItemsSelection: SunburstSmallerItems?
    @State private var selectedItem: FileNode?

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        NavigationSplitView(columnVisibility: sidebarColumnVisibility) {
            VolumeSidebar()
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: min(max(sidebarWidth, 220), 320),
                    max: 320
                )
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

                        if model.currentNode != nil {
                            Button {
                                isInspectorVisible.toggle()
                            } label: {
                                Label(
                                    isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                                    systemImage: "sidebar.trailing"
                                )
                            }
                            .keyboardShortcut("i", modifiers: [.command, .option])
                            .help(isInspectorVisible ? "Hide inspector" : "Show inspector")
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
        .tint(theme.accent)
        .frame(minWidth: isInspectorVisible ? 1100 : 760)
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
        .alert(
            "No saved scan data",
            isPresented: Binding(
                get: { model.isRequestingRescan },
                set: { isPresented in
                    if !isPresented { model.cancelPendingRescan() }
                }
            ),
            presenting: model.pendingRescanVolume
        ) { _ in
            Button("Scan Disk") {
                model.confirmPendingRescan()
            }
            Button("Cancel", role: .cancel) {
                model.cancelPendingRescan()
            }
        } message: { volume in
            Text("SpaceLens does not have a saved storage map for \(volume.name). Would you like to scan it now?")
        }
        .animation(.easeOut(duration: 0.16), value: model.errorMessage)
    }

    @ViewBuilder
    private func resultContent(current: FileNode) -> some View {
        Group {
            if isInspectorVisible {
                SpaceHorizontalSplitView(
                    trailingWidth: $inspectorWidth,
                    dividerAccessibilityLabel: "Resize inspector"
                ) {
                    chartPanel(current: current)
                } trailing: {
                    inspectorPanel(current: current)
                }
            } else {
                chartPanel(current: current)
            }
        }
        .padding(12)
    }

    private func chartPanel(current: FileNode) -> some View {
        ChartPanel(
            node: current,
            volume: model.volumeForChart(node: current),
            isProvisional: model.isScanning && model.result == nil,
            selectedItem: chartSelection,
            inspectSmallerItems: { smallerItemsSelection = $0 }
        )
        .frame(minWidth: 500)
        .allowsHitTesting(!model.isScanning || model.result != nil)
    }

    @ViewBuilder
    private func inspectorPanel(current: FileNode) -> some View {
        Group {
            if let selection = smallerItemsSelection,
               selection.chartRootID == current.id {
                SmallerItemsInspector(
                    selection: selection,
                    selectedItem: $selectedItem
                ) {
                    smallerItemsSelection = nil
                    selectedItem = nil
                }
            } else {
                ItemInspector(node: current, selectedItem: $selectedItem)
            }
        }
        .allowsHitTesting(!model.isScanning || model.result != nil)
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
            selectedItem = nil
        }
        .onChange(of: model.isScanning) {
            if model.isScanning {
                smallerItemsSelection = nil
                selectedItem = nil
            }
        }
    }

    private var sidebarColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isSidebarVisible ? .all : .detailOnly },
            set: { isSidebarVisible = $0 != .detailOnly }
        )
    }

    private var chartSelection: Binding<FileNode?> {
        Binding(
            get: { selectedItem },
            set: { item in
                selectedItem = item
                if item != nil {
                    smallerItemsSelection = nil
                }
            }
        )
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
                        .font(.title3.weight(.semibold))

                    Text(
                        "For a complete storage map, enable SpaceLens in System Settings. "
                            + "Without Full Disk Access, macOS will hide protected folders and the totals will be incomplete."
                    )
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("SpaceLens only reads file sizes. It never modifies your files.")
                        .font(.caption)
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
                        .font(.caption2)
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
                .font(.callout.weight(.medium))
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
        .shadow(color: theme.shadow.opacity(0.28), radius: 16, y: 8)
        .padding(.horizontal, 20)
    }
}
