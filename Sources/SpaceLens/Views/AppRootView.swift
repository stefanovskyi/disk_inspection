import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        HStack(spacing: 0) {
            VolumeSidebar()
                .frame(width: 264)

            Rectangle()
                .fill(theme.border)
                .frame(width: 1)

            mainContent(theme: theme)
        }
        .background(theme.background)
        .overlay(alignment: .top) {
            if let message = model.errorMessage {
                ErrorBanner(message: message) {
                    model.errorMessage = nil
                }
                .padding(.top, 46)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if model.isRequestingFullDiskAccess {
                FullDiskAccessPrompt()
                    .transition(.opacity)
            } else if model.isScanning {
                ScanProgressOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.errorMessage)
        .animation(.easeOut(duration: 0.2), value: model.isScanning)
        .animation(.easeOut(duration: 0.2), value: model.isRequestingFullDiskAccess)
    }

    @ViewBuilder
    private func mainContent(theme: SpaceTheme) -> some View {
        VStack(spacing: 0) {
            if let current = model.currentNode {
                NavigationHeader(node: current)

                HStack(spacing: 14) {
                    ChartPanel(node: current)
                        .frame(minWidth: 500)

                    ItemInspector(node: current)
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)
                }
                .padding(14)
                .padding(.top, -2)
            } else {
                WelcomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }
}

private struct FullDiskAccessPrompt: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.5 : 0.24)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("Full Disk Access recommended")
                        .font(.system(size: 20, weight: .semibold))

                    Text(
                        "For a complete storage map, enable SpaceLens in System Settings. "
                            + "Without Full Disk Access, macOS will hide protected folders and the totals will be incomplete."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                    Text("SpaceLens only reads file sizes. It never modifies your files.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 9) {
                    Button {
                        model.openFullDiskAccessSettings()
                    } label: {
                        Label("Open Full Disk Access Settings", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .foregroundStyle(Color.black.opacity(0.82))

                    Text("After enabling SpaceLens, return here and access will be checked again. macOS may ask you to reopen the app.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            model.cancelPendingDiskScan()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("Scan with Current Access") {
                            model.scanPendingDiskWithCurrentAccess()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
            .frame(width: 470)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 26, y: 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full Disk Access recommended before scanning")
    }
}

private struct ErrorBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    let dismiss: () -> Void

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 620)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.warning.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .padding(.horizontal, 20)
    }
}

private struct ScanProgressOverlay: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.38 : 0.18)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ScanningSpinner(
                    itemCount: model.progress.itemsScanned,
                    trackColor: theme.border,
                    accent: theme.accent
                )
                .frame(width: 54, height: 54)

                VStack(spacing: 5) {
                    Text("Inspecting storage")
                        .font(.system(size: 18, weight: .semibold))
                    Text(model.progress.currentPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 360)
                    Text("\(model.progress.itemsScanned.formatted()) items measured")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)

                    if let startedAt = model.scanStartedAt {
                        TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                            Label(
                                "Elapsed \(StorageFormatters.duration(max(timeline.date.timeIntervalSince(startedAt), 0)))",
                                systemImage: "clock"
                            )
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                        }
                    }

                    if model.progress.unresponsiveItems > 0 {
                        Label(
                            "\(model.progress.unresponsiveItems) unresponsive folder skipped",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.warning)
                    }
                }

                Button("Cancel") { model.cancelScan() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        }
    }
}

private struct ScanningSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let itemCount: Int
    let trackColor: Color
    let accent: Color

    var body: some View {
        Group {
            if reduceMotion {
                spinnerRing
                    .rotationEffect(.degrees(18))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let cycle = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.1) / 1.1
                    spinnerRing
                        .rotationEffect(.degrees(cycle * 360))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanning in progress")
        .accessibilityValue("\(itemCount.formatted()) items measured")
    }

    private var spinnerRing: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: 6)
            Circle()
                .trim(from: 0.08, to: 0.74)
                .stroke(
                    AngularGradient(
                        colors: [accent, .cyan, accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
        }
    }
}
