import SwiftUI

struct AIModelRuntimeDetail: View {
    @Environment(\.colorScheme) private var colorScheme
    let runtime: AIModelRuntimeReport
    let totalSize: Int64
    let actions: AIModelsViewActions
    @State private var bottomSection: BottomSection = .models

    private enum BottomSection: String, CaseIterable, Identifiable {
        case models = "Models"
        case folders = "Raw Folders"

        var id: String { rawValue }
    }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(theme: theme)
                installations(theme: theme)
                if !runtime.categories.isEmpty {
                    composition(theme: theme)
                }
                inventory(theme: theme)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func header(theme: SpaceTheme) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: runtime.systemImage)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 46, height: 46)
                .background(theme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(runtime.displayName)
                    .font(.title2.weight(.bold))
                Text(detailSubtitle)
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(StorageFormatters.bytes(runtime.size))
                    .font(.title2.weight(.semibold).monospacedDigit())
                if totalSize > 0 {
                    Text(StorageFormatters.percent(Double(runtime.size) / Double(totalSize)))
                        .font(.caption)
                        .foregroundStyle(theme.tertiaryText)
                }
            }
        }
        .foregroundStyle(theme.primaryText)
        .padding(16)
        .spacePanel()
    }

    private func installations(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Installations")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(runtime.installations.count) detected")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
            }

            if runtime.installations.isEmpty {
                Label(
                    "No recognized app, command, or source build was found in conventional locations.",
                    systemImage: "questionmark.folder"
                )
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .padding(.vertical, 8)
            } else {
                ForEach(runtime.installations) { installation in
                    HStack(spacing: 10) {
                        Image(systemName: installation.kind.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 30, height: 30)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(installation.name)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.primaryText)
                                if let version = installation.version {
                                    Text(version)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(theme.secondaryText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(theme.surface, in: Capsule())
                                }
                            }
                            Text(installation.url.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Button {
                            actions.showInFinder(installation.url)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal installation in Finder")
                        .accessibilityLabel("Reveal \(installation.name) in Finder")
                    }
                    .padding(10)
                    .background(theme.elevatedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .padding(14)
        .spacePanel()
    }

    private func composition(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage composition")
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(runtime.categories) { breakdown in
                    HStack(spacing: 8) {
                        Image(systemName: breakdown.category.systemImage)
                            .foregroundStyle(categoryColor(breakdown.category))
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(breakdown.category.displayName)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(StorageFormatters.bytes(breakdown.size))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(theme.primaryText)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(theme.elevatedSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .spacePanel()
    }

    private func inventory(theme: SpaceTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(bottomSection == .models ? "Installed Models" : "Folders & Locations")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Picker(selection: $bottomSection) {
                    ForEach(BottomSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 225)
                .accessibilityLabel("Inventory view")
            }

            if bottomSection == .models {
                modelList(theme: theme)
            } else {
                locationList(theme: theme)
            }
        }
        .padding(14)
        .spacePanel()
    }

    @ViewBuilder
    private func modelList(theme: SpaceTheme) -> some View {
        if runtime.models.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.tertiaryText)
                    .accessibilityHidden(true)
                Text(runtime.runtime.emptyDescription)
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(runtime.models) { model in
                    modelRow(model, theme: theme)
                }
            }
        }
    }

    private func modelRow(_ model: AIModelRecord, theme: SpaceTheme) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.format == .mlx ? "apple.logo" : "shippingbox.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 30, height: 30)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(model.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .textSelection(.enabled)
                    if let duplicate = model.duplicateDescription {
                        Label(duplicate, systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.warning)
                            .lineLimit(1)
                            .help(duplicate)
                    }
                }
                Text(model.subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Text(StorageFormatters.bytes(model.allocatedSize))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.primaryText)

            Menu {
                Button("Reveal in Finder") { actions.showInFinder(model.primaryURL) }
                Button("Open Containing Folder in Terminal") {
                    actions.openInTerminal(directoryForActions(model.primaryURL))
                }
                Button("Inspect Containing Folder") {
                    actions.inspectDirectory(directoryForActions(model.primaryURL))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Model actions")
            .accessibilityLabel("Actions for \(model.displayName)")
        }
        .padding(10)
        .background(theme.elevatedSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func locationList(theme: SpaceTheme) -> some View {
        if runtime.locations.isEmpty {
            Label("No known storage locations were found.", systemImage: "folder.badge.questionmark")
                .font(.callout)
                .foregroundStyle(theme.secondaryText)
                .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(runtime.locations) { location in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: location.status.isIssue ? "exclamationmark.triangle.fill" : "folder.fill")
                            .foregroundStyle(location.status.isIssue ? theme.warning : theme.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(location.name)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.primaryText)
                                if location.status != .measured {
                                    Text(location.status.displayName)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(theme.warning)
                                }
                            }
                            Text(location.url.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        Text(StorageFormatters.bytes(location.size))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(theme.primaryText)
                        Menu {
                            Button("Reveal in Finder") { actions.showInFinder(location.url) }
                            Button("Open in Terminal") { actions.openInTerminal(location.url) }
                            if location.root?.isReadable == true {
                                Button("Inspect Storage Map") { actions.inspectDirectory(location.url) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 24, height: 24)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Location actions")
                        .accessibilityLabel("Actions for \(location.name)")
                    }
                    .padding(10)
                    .background(theme.elevatedSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private var detailSubtitle: String {
        var parts = [runtime.countDescription, "\(runtime.itemCount.formatted()) items"]
        if let latest = runtime.latestModificationDate {
            parts.append("Latest change " + latest.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " · ")
    }

    private func directoryForActions(_ url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func categoryColor(_ category: AIModelStorageCategory) -> Color {
        let isDark = colorScheme == .dark
        return switch category {
        case .weights: SpacePalette.color(hue: 0.59, depth: 0, isDark: isDark)
        case .manifests: SpacePalette.color(hue: 0.12, depth: 1, isDark: isDark)
        case .logs: SpacePalette.color(hue: 0.04, depth: 2, isDark: isDark)
        case .chats: SpacePalette.color(hue: 0.82, depth: 1, isDark: isDark)
        case .runtimes: SpacePalette.color(hue: 0.47, depth: 1, isDark: isDark)
        case .applicationState: SpacePalette.color(hue: 0.67, depth: 2, isDark: isDark)
        case .other: SpacePalette.color(hue: 0.0, depth: 3, isDark: isDark)
        }
    }
}
