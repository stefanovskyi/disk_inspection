import SwiftUI

struct AppRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("layout.sidebarVisible") private var isSidebarVisible = true
    @AppStorage("layout.inspectorVisible") private var isInspectorVisible = true
    @AppStorage("layout.inspectorWidth.v2") private var inspectorWidth = Double(
        AppLayoutMetrics.preferredInspectorWidth
    )
    @State private var smallerItemsSelection: SunburstSmallerItems?
    @State private var selectedItem: FileNode?

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        HStack(spacing: 0) {
            if isSidebarVisible {
                VolumeSidebar()
                    .frame(width: AppLayoutMetrics.sidebarWidth)

                Divider()
            }

            mainContent(theme: theme)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    isSidebarVisible.toggle()
                } label: {
                    Label(
                        isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                        systemImage: "sidebar.leading"
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")

                Button {
                    model.navigateBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(model.selectedSection != .storage || !model.canNavigateBack)
                .help("Go back (⌘[)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if model.selectedSection == .aiCodingTools {
                    if model.aiCodingTools.isRunning {
                        AICodingToolsToolbarStatus(progress: model.aiCodingTools.progress)

                        Button {
                            model.cancelAICodingToolsAnalysis()
                        } label: {
                            Label("Cancel Analysis", systemImage: "xmark.circle")
                        }
                        .help("Cancel AI coding tool analysis")
                    } else {
                        Button {
                            model.analyzeAICodingTools()
                        } label: {
                            Label(
                                model.aiCodingTools.state.report == nil ? "Analyze" : "Analyze Again",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .help("Measure AI coding tool storage")
                    }

                    Button {
                        model.chooseAICodingProjectRoot()
                    } label: {
                        Label("Add Project Root", systemImage: "folder.badge.plus")
                    }
                    .help("Include AI tool worktrees from a project")
                    .contextMenu {
                        ForEach(model.aiCodingTools.projectRoots) { root in
                            Button("Remove \(root.name)") {
                                model.aiCodingTools.removeProjectRoot(root)
                            }
                            .help(root.url.path)
                        }
                    }
                } else if model.selectedSection == .aiModelsAndRuntimes {
                    if model.aiModelsAndRuntimes.isRunning {
                        AIModelsToolbarStatus(progress: model.aiModelsAndRuntimes.progress)

                        Button {
                            model.cancelAIModelsAndRuntimesAnalysis()
                        } label: {
                            Label("Cancel Analysis", systemImage: "xmark.circle")
                        }
                        .help("Cancel AI model and runtime analysis")
                    } else {
                        Button {
                            model.analyzeAIModelsAndRuntimes()
                        } label: {
                            Label(
                                model.aiModelsAndRuntimes.state.report == nil ? "Analyze" : "Analyze Again",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .help("Measure AI model and runtime storage")
                    }

                } else {
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
        .tint(theme.accent)
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
    private func resultContent(current: FileNode, showsInspector: Bool) -> some View {
        Group {
            if showsInspector {
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
            if model.selectedSection == .aiCodingTools {
                AICodingToolsView(
                    store: model.aiCodingTools,
                    actions: AICodingToolsViewActions(
                        showInFinder: { model.showInFinder(url: $0) },
                        openInTerminal: { model.openInTerminal(url: $0) },
                        inspect: { model.inspectAICodingNode($0) }
                    )
                )
            } else if model.selectedSection == .aiModelsAndRuntimes {
                AIModelsAndRuntimesView(
                    store: model.aiModelsAndRuntimes,
                    actions: AIModelsViewActions(
                        showInFinder: { model.showInFinder(url: $0) },
                        openInTerminal: { model.openInTerminal(url: $0) },
                        inspectDirectory: { model.inspectAIModelsDirectory($0) }
                    )
                )
            } else if let current = model.currentNode {
                NavigationHeader(node: current)
                resultContent(
                    current: current,
                    showsInspector: isInspectorVisible
                )
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
        .onChange(of: model.selectedSection) {
            smallerItemsSelection = nil
            selectedItem = nil
        }
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
