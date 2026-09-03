import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 26) {
            Spacer()

            OrbitIllustration()
                .frame(width: 230, height: 230)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("See where your space went")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                Text("Choose a disk from the sidebar or inspect a specific folder.\nHover, click, and follow the storage trail.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if model.isDiscoveringVolumes {
                VStack(spacing: 8) {
                    Label("Reading disk capacity…", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(theme.accent)
                        .frame(width: 190)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Reading disk capacity")
            }

            Button {
                model.chooseFolder()
            } label: {
                Label("Choose a Folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .foregroundStyle(Color.black.opacity(0.82))
            .keyboardShortcut(.defaultAction)

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "externaldrive.badge.plus")
                Text("External disks appear automatically when mounted")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.tertiaryText)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 28)
    }
}

private struct OrbitIllustration: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radii: [CGFloat] = [45, 69, 93]

            for (depth, radius) in radii.enumerated() {
                let pieces = 7 + depth * 3
                for index in 0..<pieces {
                    let start = (Double(index) / Double(pieces)) * .pi * 2
                    let variable = 0.55 + (Double((index * 7 + depth * 3) % 5) * 0.1)
                    let end = start + (.pi * 2 / Double(pieces)) * variable
                    let hue = SpacePalette.hues[(index + depth) % SpacePalette.hues.count]
                    var path = Path()
                    path.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .radians(start - .pi / 2),
                        endAngle: .radians(end - .pi / 2),
                        clockwise: false
                    )
                    context.stroke(
                        path,
                        with: .color(SpacePalette.color(hue: hue, depth: depth, isDark: colorScheme == .dark).opacity(0.78)),
                        style: StrokeStyle(lineWidth: 17, lineCap: .butt)
                    )
                }
            }
        }
    }
}
