import SwiftUI

@main
struct SpaceLensApp: App {
    @State private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Rescan") { model.rescan() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.result == nil || model.isScanning)
            }

            CommandMenu("Navigate") {
                Button("Back") { model.navigateBack() }
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(!model.canNavigateBack)
            }
        }
    }
}
