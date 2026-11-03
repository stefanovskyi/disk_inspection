import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let volumes: [VolumeInfo]

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text("Keyboard Shortcuts")
                    .font(.title2.weight(.semibold))
            }

            HStack(alignment: .top, spacing: 20) {
                shortcutGroup(.navigation, theme: theme)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 14) {
                    shortcutGroup(.panels, theme: theme)
                    shortcutGroup(.scanning, theme: theme)
                    shortcutGroup(.help, theme: theme)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 20) {
                Text("Return opens the selected folder or activates a dialog’s default action. Escape closes dialogs.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .hoverFeedback(.control)
            }
        }
        .padding(24)
        .frame(width: 800)
        .foregroundStyle(theme.primaryText)
        .background(theme.background)
    }

    private func shortcutGroup(_ group: AppShortcut.Group, theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            VStack(spacing: 0) {
                ForEach(AppShortcut.allCases.filter { $0.group == group }) { shortcut in
                    shortcutRow(shortcut, theme: theme)
                }
            }
            .padding(6)
            .spacePanel()
        }
    }

    private func shortcutRow(_ shortcut: AppShortcut, theme: SpaceTheme) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.title)
                    .font(.callout)
                if let detail = detail(for: shortcut) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(shortcut.displayText)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 5))
                if let alternate = shortcut.alternateDisplayText {
                    Text("or \(alternate)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func detail(for shortcut: AppShortcut) -> String? {
        if shortcut == .toggleInspector { return "Storage Map only" }
        if AppShortcut.driveShortcuts.contains(shortcut) {
            return shortcut.volume(in: volumes)?.name ?? "Not mounted"
        }
        return nil
    }
}
