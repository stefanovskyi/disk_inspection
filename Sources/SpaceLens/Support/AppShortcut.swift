import SwiftUI

/// Shared by menu commands and the keyboard shortcut reference.
enum AppShortcut: String, CaseIterable, Identifiable {
    case toggleSidebar, toggleInspector
    case aiCodingTools, aiModels, developerStorage, mainDrive, secondDrive, thirdDrive, back
    case scanFolder, refresh
    case showShortcuts

    enum Group: String, CaseIterable, Identifiable {
        case panels = "Panels"
        case navigation = "Navigation"
        case scanning = "Scanning and Analysis"
        case help = "Help"

        var id: String { rawValue }
    }

    static let driveShortcuts: [Self] = [.mainDrive, .secondDrive, .thirdDrive]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleSidebar: return "Show or Hide Sidebar"
        case .toggleInspector: return "Show or Hide Inspector"
        case .aiCodingTools: return "AI Coding Tools"
        case .aiModels: return "AI Models"
        case .developerStorage: return "Developer Storage"
        case .mainDrive: return "Main Drive"
        case .secondDrive: return "Second Drive"
        case .thirdDrive: return "Third Drive"
        case .back: return "Back"
        case .scanFolder: return "Scan Folder…"
        case .refresh: return "Rescan or Analyze Again"
        case .showShortcuts: return "Keyboard Shortcuts"
        }
    }

    var group: Group {
        switch self {
        case .toggleSidebar, .toggleInspector: return .panels
        case .aiCodingTools, .aiModels, .developerStorage, .mainDrive, .secondDrive, .thirdDrive, .back:
            return .navigation
        case .scanFolder, .refresh: return .scanning
        case .showShortcuts: return .help
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .toggleSidebar, .toggleInspector: return "b"
        case .aiCodingTools: return "1"
        case .aiModels: return "2"
        case .developerStorage: return "3"
        case .mainDrive: return "4"
        case .secondDrive: return "5"
        case .thirdDrive: return "6"
        case .back: return "["
        case .scanFolder: return "o"
        case .refresh: return "r"
        case .showShortcuts: return "/"
        }
    }

    var shortcut: KeyboardShortcut {
        KeyboardShortcut(key, modifiers: self == .toggleInspector ? [.command, .shift] : [.command])
    }

    var displayText: String {
        (self == .toggleInspector ? "⇧⌘" : "⌘") + String(key.character).uppercased()
    }

    var alternateShortcut: KeyboardShortcut? {
        switch self {
        case .toggleSidebar: return KeyboardShortcut("s", modifiers: [.command, .control])
        case .toggleInspector: return KeyboardShortcut("i", modifiers: [.command, .option])
        default: return nil
        }
    }

    var alternateDisplayText: String? {
        switch self {
        case .toggleSidebar: return "⌃⌘S"
        case .toggleInspector: return "⌥⌘I"
        default: return nil
        }
    }

    /// The startup disk keeps its slot even when unavailable. Other disks follow
    /// the sidebar's mounted-volume order and never include selected folders.
    func volume(in volumes: [VolumeInfo]) -> VolumeInfo? {
        if self == .mainDrive { return volumes.first(where: \.isStartupVolume) }
        let index: Int
        switch self {
        case .secondDrive: index = 0
        case .thirdDrive: index = 1
        default: return nil
        }
        let otherVolumes = volumes.filter { !$0.isStartupVolume }
        return otherVolumes.indices.contains(index) ? otherVolumes[index] : nil
    }
}
