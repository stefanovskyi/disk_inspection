import SwiftUI

struct AppRootView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isSidebarVisible: Bool
    @Binding var isInspectorVisible: Bool
    @Binding var isShowingKeyboardShortcuts: Bool
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
                .keyboardShortcut(AppShortcut.toggleSidebar.alternateShortcut)
                .help(isSidebarVisible ? "Hide sidebar (⌘B)" : "Show sidebar (⌘B)")

                Button {
                    model.navigateBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!model.canNavigateBack)
                .help("Go back (⌘[)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if model.selectedSection == .aiCodingTools {
                    Button {
                        model.analyzeAICodingTools()
                    } label: {
                        Label(
                            model.aiCodingTools.state.report == nil ? "Analyze" : "Analyze Again",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .help("Measure AI coding tool storage")
                    .disabled(model.isAnalysisActive(.aiCodingTools))

                    Button {
                        model.chooseAICodingProjectRoot()
                    } label: {
                        Label("Add Project Root", systemImage: "folder.badge.plus")
                    }
                    .help("Include AI tool worktrees from a project")
                    .disabled(model.isInScanEverything(.aiCodingTools))
                    .contextMenu {
                        ForEach(model.aiCodingTools.projectRoots) { root in
                            Button("Remove \(root.name)") {
                                model.removeAICodingProjectRoot(root)
                            }
                            .help(root.url.path)
                        }
                    }
                } else if model.selectedSection == .aiModelsAndRuntimes {
                    Button {
                        model.analyzeAIModelsAndRuntimes()
                    } label: {
                        Label(
                            model.aiModelsAndRuntimes.state.report == nil ? "Analyze" : "Analyze Again",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .help("Measure AI model and runtime storage")
                    .disabled(model.isAnalysisActive(.aiModelsAndRuntimes))

                } else if model.selectedSection == .developerStorage {
                    Button {
                        model.analyzeDeveloperStorage()
                    } label: {
                        Label(
                            model.developerStorage.state.report == nil ? "Analyze" : "Analyze Again",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .help("Measure developer storage")
                    .disabled(model.isAnalysisActive(.developerStorage))

                    Button {
                        model.chooseDeveloperProjectsFolder()
                    } label: {
                        Label("Add Projects Folder", systemImage: "folder.badge.plus")
                    }
                    .help("Find generated artifacts below a projects folder")
                    .disabled(model.isInScanEverything(.developerStorage))
                    .contextMenu {
                        ForEach(model.developerStorage.projectContainers) { container in
                            Button("Remove \(container.name)") {
                                model.removeDeveloperProjectContainer(container)
                            }
                            .help(container.url.path)
                        }
                    }

                } else {
                    if model.result != nil {
                        Button {
                            model.rescan()
                        } label: {
                            Label("Rescan", systemImage: "arrow.clockwise")
                        }
                        .help("Scan this location again (⌘R)")
                        .disabled(!model.canRefreshCurrentSection)
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
                        .keyboardShortcut(AppShortcut.toggleInspector.alternateShortcut)
                        .help(isInspectorVisible ? "Hide inspector (⇧⌘B)" : "Show inspector (⇧⌘B)")
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
        .background {
            MouseBackNavigation {
                guard model.canNavigateBack else { return false }
                model.navigateBack()
                return true
            }
            .frame(width: 0, height: 0)
        }
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
                    if !isPresented { model.cancelPendingFullDiskOperation() }
                }
            )
        ) {
            FullDiskAccessPrompt()
        }
        .sheet(isPresented: $isShowingKeyboardShortcuts) {
            KeyboardShortcutsView(volumes: model.volumes)
        }
        .alert(
            "\(model.pendingScanEverythingPlan?.scope.title ?? "Continue")?",
            isPresented: Binding(
                get: { model.isRequestingScanEverything },
                set: { isPresented in
                    if !isPresented { model.cancelScanEverythingConfirmation() }
                }
            ),
            presenting: model.pendingScanEverythingPlan
        ) { _ in
            Button(model.pendingScanEverythingPlan?.scope.title ?? "Continue") {
                model.confirmScanEverything()
            }
            Button("Cancel", role: .cancel) {
                model.cancelScanEverythingConfirmation()
            }
        } message: { plan in
            Text(batchConfirmationMessage(for: plan))
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
        .onChange(of: model.activityCount) { previousCount, count in
            // The sidebar is the only place progress is shown.
            if count > previousCount { isSidebarVisible = true }
        }
    }

    @ViewBuilder
    private func resultContent(current: FileNode, showsInspector: Bool) -> some View {
        Group {
            if model.isScanning && model.result == nil {
                // The live chart stays visible while facts replace the partial inspector.
                HStack(spacing: 12) {
                    chartPanel(current: current)
                    ScanFactsView(topic: .diskStorage, source: .presentedScan, layout: .panel)
                        .frame(width: AppLayoutMetrics.scanFactsPanelWidth)
                        .spacePanel()
                }
            } else if showsInspector {
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
                    isInBatch: model.isInScanEverything(.aiCodingTools),
                    actions: AICodingToolsViewActions(
                        selectTool: { model.selectAICodingTool($0) },
                        analyze: { model.analyzeAICodingTools() },
                        showInFinder: { model.showInFinder(url: $0) },
                        openInTerminal: { model.openInTerminal(url: $0) },
                        inspect: { model.inspectAICodingNode($0) }
                    )
                )
            } else if model.selectedSection == .aiModelsAndRuntimes {
                AIModelsAndRuntimesView(
                    store: model.aiModelsAndRuntimes,
                    isInBatch: model.isInScanEverything(.aiModelsAndRuntimes),
                    actions: AIModelsViewActions(
                        selectRuntime: { model.selectAIModelRuntime($0) },
                        analyze: { model.analyzeAIModelsAndRuntimes() },
                        showInFinder: { model.showInFinder(url: $0) },
                        openInTerminal: { model.openInTerminal(url: $0) },
                        inspectDirectory: { model.inspectAIModelsDirectory($0) }
                    )
                )
            } else if model.selectedSection == .developerStorage {
                DeveloperStorageView(
                    store: model.developerStorage,
                    isInBatch: model.isInScanEverything(.developerStorage),
                    actions: DeveloperStorageViewActions(
                        selectEcosystem: { model.selectDeveloperEcosystem($0) },
                        analyze: { model.analyzeDeveloperStorage() },
                        showInFinder: { model.showInFinder(url: $0) },
                        openInTerminal: { model.openInTerminal(url: $0) },
                        inspectDirectory: { model.inspectDeveloperStorageDirectory($0) }
                    )
                )
            } else if let current = model.currentNode {
                NavigationHeader(node: current)
                FoldableScanFacts(topic: .diskStorage, source: model.storageRefreshSource) {
                    resultContent(
                        current: current,
                        showsInspector: isInspectorVisible
                    )
                }
            } else if let volume = model.selectedVolumeOverview,
                      model.previousScanRoot == nil,
                      model.isInScanEverything(volume) {
                ScanFactsView(topic: .diskStorage, source: .volume(volume))
            } else if let volume = model.selectedVolumeOverview {
                FoldableScanFacts(topic: .diskStorage, source: model.storageRefreshSource) {
                    DiskOverview(
                        volume: volume,
                        previousSummary: model.previousScanSummary,
                        previousRoot: model.previousScanRoot
                    )
                }
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

    private func batchConfirmationMessage(for plan: ScanEverythingPlan) -> String {
        switch plan.scope {
        case .discScan:
            return "SpaceLens will scan \(plan.volumes.count) mounted local "
                + (plan.volumes.count == 1 ? "disk" : "disks")
                + ". The scan is read-only and may take several minutes."
        case .analysis:
            return "SpaceLens will run AI Coding Tools, AI Models, and Developer Storage analysis. "
                + "The analysis is read-only and may take several minutes."
        case .combined:
            return "SpaceLens will scan \(plan.volumes.count) mounted local "
                + (plan.volumes.count == 1 ? "disk" : "disks")
                + " and run \(plan.analyses.count) storage analyses. "
                + "The operation is read-only and may take several minutes."
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
                    Text("Full Disk Access required")
                        .font(.title3.weight(.semibold))

                    Text(
                        "SpaceLens checks Full Disk Access before every scan and analysis. "
                            + "Enable it in System Settings so protected folders are not silently omitted."
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

                    Text("After enabling SpaceLens, return here and access will be checked again. If macOS asks you to reopen the app, start the scan or analysis again.")
                        .font(.caption2)
                        .foregroundStyle(theme.tertiaryText)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            model.cancelPendingFullDiskOperation()
                        }
                        .keyboardShortcut(.cancelAction)
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
        .accessibilityLabel("Full Disk Access required before scanning or analysis")
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
