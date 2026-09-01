import SwiftUI

@main
struct SpaceLensApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .defaultSize(width: 1320, height: 820)
        .windowStyle(.hiddenTitleBar)
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
