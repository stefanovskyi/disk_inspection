import AppKit
import SwiftUI

/// Loads bundled logos once and keeps them for the app session.
@MainActor
private enum BrandLogoImages {
    /// The packaged app carries the SwiftPM resource bundle in `Contents/Resources`;
    /// `Bundle.module` only resolves it next to the executable for `swift run`.
    private static let directory: URL = {
        let packaged = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("SpaceLens_SpaceLens.bundle"))
        }
        let bundle = packaged ?? Bundle.module
        return (bundle.resourceURL ?? bundle.bundleURL).appendingPathComponent("BrandLogos", isDirectory: true)
    }()

    private static var images: [String: NSImage] = [:]

    static func image(for logo: BrandLogo) -> NSImage? {
        if let image = images[logo.assetName] { return image }
        let url = directory.appendingPathComponent(logo.assetName).appendingPathExtension("png")
        let image = NSImage(contentsOf: url)
        images[logo.assetName] = image
        return image
    }
}

/// Resolves real application icons off the main actor. The serial queue means a
/// stalled disk can hold at most one thread and never freezes the interface.
private final class ApplicationIconLoader: @unchecked Sendable {
    static let shared = ApplicationIconLoader()

    private let queue = DispatchQueue(label: "SpaceLens.ApplicationIconLoader", qos: .utility)
    private let lock = NSLock()
    /// A stored `nil` records that no matching application is installed.
    private var icons: [ApplicationIconSource: NSImage?] = [:]

    func cachedIcon(for source: ApplicationIconSource) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return icons[source] ?? nil
    }

    func icon(for source: ApplicationIconSource) async -> NSImage? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                lock.lock()
                let cached = icons[source]
                lock.unlock()
                if let cached {
                    continuation.resume(returning: cached)
                    return
                }

                let icon = Self.applicationURL(for: source).map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
                lock.lock()
                icons[source] = .some(icon)
                lock.unlock()
                continuation.resume(returning: icon)
            }
        }
    }

    private static func applicationURL(for source: ApplicationIconSource) -> URL? {
        switch source {
        case .bundle(let url):
            return url
        case .bundleIdentifier(let identifier):
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        case .applicationNamed(let name):
            let directories = [
                "/Applications",
                "/System/Applications",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
            ]
            return directories
                .map { URL(fileURLWithPath: $0).appendingPathComponent("\(name).app", isDirectory: true) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
}

/// A bundled logo, legible on both light and dark surfaces.
struct BrandLogoImage: View {
    @Environment(\.colorScheme) private var colorScheme
    let logo: BrandLogo
    let size: CGFloat

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        Group {
            if let image = BrandLogoImages.image(for: logo) {
                switch logo.appearance {
                case .original:
                    artwork(image)
                case .monochrome:
                    artwork(image, renderingMode: .template)
                        .foregroundStyle(theme.primaryText)
                case .lightBacked:
                    if colorScheme == .dark {
                        artwork(image)
                            .padding(size * 0.1)
                            .background(.white, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    } else {
                        artwork(image)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func artwork(_ image: NSImage, renderingMode: Image.TemplateRenderingMode = .original) -> some View {
        Image(nsImage: image)
            .renderingMode(renderingMode)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

/// A product's logo, or a symbol for entries with no brand of their own.
struct BrandOrSymbolIcon: View {
    let logo: BrandLogo?
    let systemImage: String
    let size: CGFloat
    let tint: Color

    var body: some View {
        if let logo {
            BrandLogoImage(logo: logo, size: size)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.8, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// The name chips listed on analysis landing pages.
struct BrandChipLabel: View {
    let title: String
    let logo: BrandLogo?
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            BrandOrSymbolIcon(logo: logo, systemImage: systemImage, size: 16, tint: tint)
        }
    }
}

/// An installed application's real icon, showing `fallback` until it loads or
/// when the application is missing.
struct ApplicationIconImage<Fallback: View>: View {
    let source: ApplicationIconSource
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback
    @State private var loaded: (source: ApplicationIconSource, icon: NSImage?)?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                fallback()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: source) {
            let icon = await ApplicationIconLoader.shared.icon(for: source)
            loaded = (source, icon)
        }
    }

    private var icon: NSImage? {
        if let loaded, loaded.source == source { return loaded.icon }
        return ApplicationIconLoader.shared.cachedIcon(for: source)
    }
}

/// Identifies a scanned item by its real application icon or brand logo.
/// Logos sit slightly inside `size` because application icons include margins.
struct StorageItemIconView<Fallback: View>: View {
    let icon: StorageItemIcon
    let size: CGFloat
    @ViewBuilder let fallback: () -> Fallback

    init(
        url: URL,
        isDirectory: Bool,
        size: CGFloat,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        icon = StorageItemIcon.resolve(url: url, isDirectory: isDirectory)
        self.size = size
        self.fallback = fallback
    }

    var body: some View {
        switch icon {
        case .application(let source, let brand):
            ApplicationIconImage(source: source, size: size) {
                if let brand {
                    brandLogo(brand)
                } else {
                    fallback()
                }
            }
        case .brand(let logo):
            brandLogo(logo)
        case .generic:
            fallback()
        }
    }

    private func brandLogo(_ logo: BrandLogo) -> some View {
        BrandLogoImage(logo: logo, size: size * 0.78)
            .frame(width: size, height: size)
    }
}
