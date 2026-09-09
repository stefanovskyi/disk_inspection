import SwiftUI

struct SpaceTheme {
    let background: Color
    let sidebar: Color
    let surface: Color
    let elevatedSurface: Color
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color
    let warning: Color

    init(colorScheme: ColorScheme) {
        background = Color(nsColor: .windowBackgroundColor)
        sidebar = Color(nsColor: .windowBackgroundColor)
        surface = Color(nsColor: .controlBackgroundColor)
        elevatedSurface = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        border = Color(nsColor: .separatorColor)
        primaryText = Color(nsColor: .labelColor)
        secondaryText = Color(nsColor: .secondaryLabelColor)
        tertiaryText = Color(nsColor: .tertiaryLabelColor)
        accent = Color(nsColor: .controlAccentColor)
        warning = Color(nsColor: .systemOrange)
    }
}

enum SpacePalette {
    static let hues: [Double] = [
        0.43, // mint
        0.50, // cyan
        0.58, // blue
        0.72, // violet
        0.88, // magenta
        0.98, // coral
        0.08, // amber
        0.18  // lime
    ]

    static func color(hue: Double, depth: Int, isDark: Bool) -> Color {
        let saturation = max(0.48, 0.78 - Double(depth) * 0.045)
        let baseBrightness = isDark ? 0.88 : 0.68
        let brightness = min(isDark ? 0.98 : 0.88, baseBrightness + Double(depth) * 0.025)
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

struct PanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        content
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
    }
}

extension View {
    func spacePanel() -> some View { modifier(PanelModifier()) }
}
