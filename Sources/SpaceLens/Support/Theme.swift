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
    let selectionSurface: Color
    let selectionBorder: Color
    let chartHighlight: Color
    let shadow: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            background = Self.rgb(0x12171C)
            sidebar = Self.rgb(0x171D22)
            surface = Self.rgb(0x1B2228)
            elevatedSurface = Self.rgb(0x283139)
            border = Self.rgb(0x394650)
            primaryText = Self.rgb(0xE7EDF2)
            secondaryText = Self.rgb(0xB6C2CC)
            tertiaryText = Self.rgb(0x8E9DA9)
            accent = Self.rgb(0x35B8C8)
            warning = Self.rgb(0xF07A8A)
            selectionSurface = Self.rgb(0x183943)
            selectionBorder = Self.rgb(0x327989)
            chartHighlight = Self.rgb(0xDCEAF0)
            shadow = Self.rgb(0x0A0F14)
        } else {
            background = Self.rgb(0xF1F4F7)
            sidebar = Self.rgb(0xE9EEF2)
            surface = Self.rgb(0xF8FAFB)
            elevatedSurface = Self.rgb(0xDEE5EB)
            border = Self.rgb(0xC5CFD8)
            primaryText = Self.rgb(0x18232E)
            secondaryText = Self.rgb(0x445464)
            tertiaryText = Self.rgb(0x5C6C7D)
            accent = Self.rgb(0x0B7185)
            warning = Self.rgb(0xB0445A)
            selectionSurface = Self.rgb(0xD5E8EC)
            selectionBorder = Self.rgb(0x82BBC4)
            chartHighlight = Self.rgb(0x233644)
            shadow = Self.rgb(0x26323C)
        }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum SpacePalette {
    static let hues: [Double] = [
        0.46, // teal
        0.53, // cyan blue
        0.60, // blue
        0.69, // indigo
        0.78, // violet
        0.88, // magenta
        0.96, // rose
        0.35  // emerald
    ]

    static func color(hue: Double, depth: Int, isDark: Bool) -> Color {
        let saturation = max(0.52, (isDark ? 0.72 : 0.68) - Double(depth) * 0.035)
        let baseBrightness = isDark ? 0.84 : 0.61
        let brightness = min(isDark ? 0.94 : 0.76, baseBrightness + Double(depth) * 0.03)
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
