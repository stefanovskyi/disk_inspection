import SwiftUI

@main
struct SpaceLensApp: App {
    @State private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
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
                Button("Scan Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command])
                    .disabled(model.isScanningEverything)
                Button("Scan Everything…") { model.requestScanEverything() }
                    .disabled(model.isDiscoveringVolumes || model.isScanningEverything)
                Button(model.selectedSection == .storage ? "Rescan" : "Analyze Again") {
                    model.refreshCurrentSection()
                }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!model.canRefreshCurrentSection)
            }

            CommandMenu("Navigate") {
                Button("Back") { model.navigateBack() }
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(!model.canNavigateBack)
            }
        }
    }
}
