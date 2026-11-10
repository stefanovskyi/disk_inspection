import SwiftUI

@main
struct SpaceLensApp: App {
    @State private var model: AppViewModel
    @AppStorage("layout.sidebarVisible") private var isSidebarVisible = true
    @AppStorage("layout.inspectorVisible") private var isInspectorVisible = true
    @State private var isShowingKeyboardShortcuts = false

    init() {
        // Clear storage before the model or any view reads it.
        if ProcessInfo.processInfo.arguments.contains(LocalStorageReset.relaunchArgument) {
            LocalStorageReset.forCurrentApplication().perform()
        }
        _model = State(initialValue: AppViewModel())
    }

    var body: some Scene {
        WindowGroup(ProcessInfo.processInfo.arguments.contains("--chart-style-prototype") ? "SpaceLens · Holo Pulse preview" : "SpaceLens") {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--chart-style-prototype") {
                    ChartStylePrototypeView()
                } else {
                    AppRootView(
                        isSidebarVisible: $isSidebarVisible,
                        isInspectorVisible: $isInspectorVisible,
                        isShowingKeyboardShortcuts: $isShowingKeyboardShortcuts
                    )
                }
            }
                .environment(model)
                .frame(
                    minWidth: AppLayoutMetrics.minimumWindowWidth,
                    minHeight: AppLayoutMetrics.minimumWindowHeight
                )
        }
        .defaultSize(width: 1320, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button(AppShortcut.scanFolder.title) { model.chooseFolder() }
                    .keyboardShortcut(AppShortcut.scanFolder.shortcut)
                Button("Disc Scan…") { model.requestDiscScan() }
                    .disabled(!model.canRequestDiscScan)
                Button("Analysis…") { model.requestAllAnalyses() }
                    .disabled(!model.canRequestAllAnalyses)
                Button(model.selectedSection == .storage ? "Rescan" : "Analyze Again") {
                    model.refreshCurrentSection()
                }
                    .keyboardShortcut(AppShortcut.refresh.shortcut)
                    .disabled(!model.canRefreshCurrentSection)
            }

            CommandGroup(after: .saveItem) {
                Divider()
                Button("Reset SpaceLens…") { model.requestLocalStorageReset() }
                    .help("Clear saved scans and preferences, then reopen SpaceLens as on first launch")
            }

            CommandMenu("Navigate") {
                Button(AppShortcut.back.title) { model.navigateBack() }
                    .keyboardShortcut(AppShortcut.back.shortcut)
                    .disabled(!model.canNavigateBack)

                Divider()

                Button(AppShortcut.aiCodingTools.title) { model.showAICodingTools() }
                    .keyboardShortcut(AppShortcut.aiCodingTools.shortcut)
                Button(AppShortcut.aiModels.title) { model.showAIModelsAndRuntimes() }
                    .keyboardShortcut(AppShortcut.aiModels.shortcut)
                Button(AppShortcut.developerStorage.title) { model.showDeveloperStorage() }
                    .keyboardShortcut(AppShortcut.developerStorage.shortcut)

                Divider()

                ForEach(AppShortcut.driveShortcuts) { shortcut in
                    Button(shortcut.title) {
                        if let volume = shortcut.volume(in: model.volumes) {
                            model.selectVolume(volume)
                        }
                    }
                    .keyboardShortcut(shortcut.shortcut)
                    .disabled(shortcut.volume(in: model.volumes) == nil)
                }
            }

            CommandGroup(after: .sidebar) {
                Button(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    isSidebarVisible.toggle()
                }
                .keyboardShortcut(AppShortcut.toggleSidebar.shortcut)

                Button(isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    isInspectorVisible.toggle()
                }
                .keyboardShortcut(AppShortcut.toggleInspector.shortcut)
                .disabled(model.selectedSection != .storage || model.currentNode == nil)
            }

            CommandGroup(after: .help) {
                Button(AppShortcut.showShortcuts.title) {
                    isShowingKeyboardShortcuts = true
                }
                .keyboardShortcut(AppShortcut.showShortcuts.shortcut)
            }
        }
    }
}
