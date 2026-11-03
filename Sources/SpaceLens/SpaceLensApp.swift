import SwiftUI

@main
struct SpaceLensApp: App {
    @State private var model = AppViewModel()

    var body: some Scene {
        WindowGroup(ProcessInfo.processInfo.arguments.contains("--chart-style-prototype") ? "SpaceLens · Hyperspace lab" : "SpaceLens") {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--chart-style-prototype") {
                    ChartStylePrototypeView()
                } else {
                    AppRootView()
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
                Button("Scan Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Disc Scan…") { model.requestDiscScan() }
                    .disabled(!model.canRequestDiscScan)
                Button("Analysis…") { model.requestAllAnalyses() }
                    .disabled(!model.canRequestAllAnalyses)
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
