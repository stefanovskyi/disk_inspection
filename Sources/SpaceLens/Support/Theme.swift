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
        if colorScheme == .dark {
            background = Color(red: 0.055, green: 0.067, blue: 0.085)
            sidebar = Color(red: 0.075, green: 0.090, blue: 0.115)
            surface = Color(red: 0.095, green: 0.112, blue: 0.140)
            elevatedSurface = Color(red: 0.125, green: 0.145, blue: 0.180)
            border = Color.white.opacity(0.10)
            primaryText = Color(red: 0.94, green: 0.96, blue: 0.98)
            secondaryText = Color(red: 0.66, green: 0.71, blue: 0.78)
            tertiaryText = Color(red: 0.45, green: 0.50, blue: 0.58)
        } else {
            background = Color(red: 0.945, green: 0.955, blue: 0.970)
            sidebar = Color(red: 0.975, green: 0.980, blue: 0.990)
            surface = .white
            elevatedSurface = Color(red: 0.925, green: 0.940, blue: 0.965)
            border = Color.black.opacity(0.10)
            primaryText = Color(red: 0.06, green: 0.085, blue: 0.13)
            secondaryText = Color(red: 0.30, green: 0.35, blue: 0.43)
            tertiaryText = Color(red: 0.48, green: 0.52, blue: 0.59)
        }

        accent = Color(red: 0.25, green: 0.88, blue: 0.70)
        warning = Color(red: 1.00, green: 0.72, blue: 0.30)
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
    }
}

extension View {
    func spacePanel() -> some View { modifier(PanelModifier()) }
}
