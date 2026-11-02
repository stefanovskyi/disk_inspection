import SwiftUI

struct VolumeSidebar: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var internalVolumes: [VolumeInfo] { model.volumes.filter { !$0.isExternal } }
    private var externalVolumes: [VolumeInfo] { model.volumes.filter(\.isExternal) }

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            brand(theme: theme)

            List {
                Section {
                    Button {
                        model.showAICodingTools()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(theme.accent)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Coding Tools")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.primaryText)
                                if let analysisSubtitle {
                                    Text(analysisSubtitle)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(theme.tertiaryText)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 4)

                            if model.isAnalysisActive(.aiCodingTools) {
                                ProgressView()
                                    .controlSize(.small)
                            } else if model.aiCodingTools.state.report != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                        }
                        .padding(11)
                        .contentShape(Rectangle())
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(model.selectedSection == .aiCodingTools ? theme.selectionSurface : Color.clear)
                                .overlay {
                                    if model.selectedSection == .aiCodingTools {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(theme.selectionBorder, lineWidth: 1)
                                    }
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityHint("Shows storage used by supported AI coding tools")

                    Button {
                        model.showAIModelsAndRuntimes()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "cpu")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(theme.accent)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Models")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.primaryText)
                                if let aiModelsAnalysisSubtitle {
                                    Text(aiModelsAnalysisSubtitle)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(theme.tertiaryText)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 4)

                            if model.isAnalysisActive(.aiModelsAndRuntimes) {
                                ProgressView()
                                    .controlSize(.small)
                            } else if model.aiModelsAndRuntimes.state.report != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                        }
                        .padding(11)
                        .contentShape(Rectangle())
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    model.selectedSection == .aiModelsAndRuntimes
                                        ? theme.selectionSurface
                                        : Color.clear
                                )
                                .overlay {
                                    if model.selectedSection == .aiModelsAndRuntimes {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(theme.selectionBorder, lineWidth: 1)
                                    }
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityHint("Shows storage used by local AI models and inference runtimes")

                    Button {
                        model.showDeveloperStorage()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(theme.accent)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Developer Storage")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.primaryText)
                                if let developerStorageSubtitle {
                                    Text(developerStorageSubtitle)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(theme.tertiaryText)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 4)

                            if model.isAnalysisActive(.developerStorage) {
                                ProgressView().controlSize(.small)
                            } else if model.developerStorage.state.report != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                        }
                        .padding(11)
                        .contentShape(Rectangle())
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(model.selectedSection == .developerStorage ? theme.selectionSurface : Color.clear)
                                .overlay {
                                    if model.selectedSection == .developerStorage {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(theme.selectionBorder, lineWidth: 1)
                                    }
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityHint("Shows storage used by supported development ecosystems")
                } header: {
                    sectionHeader("Analysis", theme: theme)
                }

                volumeSection("This Mac", volumes: internalVolumes, theme: theme)

                if !externalVolumes.isEmpty {
                    volumeSection("External", volumes: externalVolumes, theme: theme)
                }

                if !model.sessionFolders.isEmpty {
                    sessionFolderSection(theme: theme)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onDeleteCommand(perform: removeSelectedFolder)
            .frame(minHeight: AppLayoutMetrics.sidebarListMinimumHeight)

            VStack(spacing: 9) {
                ScanEverythingControl()

                Button {
                    if model.selectedSection == .developerStorage {
                        model.chooseDeveloperProjectsFolder()
                    } else if model.selectedSection == .aiModelsAndRuntimes {
                        model.chooseAdditionalAIModelRoot()
                    } else {
                        model.chooseFolder()
                    }
                } label: {
                    Label(primaryFolderButtonTitle, systemImage: "folder.badge.plus")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
                .disabled(isPrimaryFolderButtonDisabled)
                .help(
                    primaryFolderButtonHelp
                )
                .contextMenu {
                    if model.selectedSection == .aiModelsAndRuntimes {
                        ForEach(model.aiModelsAndRuntimes.additionalRoots) { root in
                            Button("Remove \(root.name)") {
                                model.removeAdditionalAIModelRoot(root)
                            }
                            .help(root.url.path)
                        }
                    } else if model.selectedSection == .developerStorage {
                        ForEach(model.developerStorage.projectContainers) { container in
                            Button("Remove \(container.name)") {
                                model.removeDeveloperProjectContainer(container)
                            }
                            .help(container.url.path)
                        }
                    }
                }

                Button {
                    model.refreshVolumes()
                } label: {
                    Label("Refresh Disks", systemImage: "arrow.clockwise")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)
                .accessibilityHint("Refreshes the list of mounted disks")
            }
            .padding(14)
            .background(theme.surface)
            // Cards claim the room they need first; the list above scrolls in what remains.
            .layoutPriority(1)
        }
        .background(theme.sidebar)
    }

    private func brand(theme: SpaceTheme) -> some View {
        Button {
            model.showDiskList()
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(theme.elevatedSurface)
                    Circle()
                        .trim(from: 0.04, to: 0.78)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(5)
                    Circle()
                        .trim(from: 0.16, to: 0.56)
                        .stroke(
                            SpacePalette.color(
                                hue: 0.60,
                                depth: 1,
                                isDark: colorScheme == .dark
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .padding(10)
                }
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SpaceLens")
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(theme.primaryText)
                    Text("Storage inspector")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.tertiaryText)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.top, 12)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Back to disks")
        .accessibilityLabel("SpaceLens home")
        .accessibilityHint("Returns to the list of disks")
    }

    @ViewBuilder
    private func volumeSection(_ title: String, volumes: [VolumeInfo], theme: SpaceTheme) -> some View {
        Section {
            if volumes.isEmpty {
                Text(title == "External" ? "No external disks mounted" : "No disks found")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.vertical, 10)
            } else {
                ForEach(volumes) { volume in
                    VolumeRow(
                        volume: volume,
                        showsLocation: volumes.filter { $0.name == volume.name }.count > 1,
                        isSelected: activeLocationPath == volume.url.standardizedFileURL.path
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            sectionHeader(title, theme: theme)
        }
    }

    private func sessionFolderSection(theme: SpaceTheme) -> some View {
        Section {
            ForEach(model.sessionFolders) { folder in
                SessionFolderRow(
                    folder: folder,
                    isSelected: activeLocationPath == folder.id
                )
                    .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        } header: {
            sectionHeader("Folders", theme: theme)
        }
    }

    private func sectionHeader(_ title: String, theme: SpaceTheme) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.secondaryText)
            .textCase(nil)
    }

    private var activeLocationPath: String? {
        guard model.selectedSection == .storage else { return nil }
        return model.presentedScan?.path
            ?? model.result?.root.url.standardizedFileURL.path
            ?? model.selectedVolumeOverview?.url.standardizedFileURL.path
    }

    private var analysisSubtitle: String? {
        if let operation = model.scanEverythingOperation(for: .aiCodingTools) {
            return StorageFormatters.bytes(operation.mappedBytes)
        }
        if model.aiCodingTools.isRunning {
            return StorageFormatters.bytes(model.aiCodingTools.progress.mappedBytes)
        }
        if let report = model.aiCodingTools.state.report {
            return StorageFormatters.bytes(report.totalSize)
        }
        return nil
    }

    private var aiModelsAnalysisSubtitle: String? {
        if let operation = model.scanEverythingOperation(for: .aiModelsAndRuntimes) {
            return StorageFormatters.bytes(operation.mappedBytes)
        }
        if model.aiModelsAndRuntimes.isRunning {
            return StorageFormatters.bytes(model.aiModelsAndRuntimes.progress.mappedBytes)
        }
        if let report = model.aiModelsAndRuntimes.state.report {
            return StorageFormatters.bytes(report.totalSize)
        }
        return nil
    }

    private var developerStorageSubtitle: String? {
        if let operation = model.scanEverythingOperation(for: .developerStorage) {
            return StorageFormatters.bytes(operation.mappedBytes)
        }
        if model.developerStorage.isRunning {
            return StorageFormatters.bytes(model.developerStorage.progress.mappedBytes)
        }
        if let report = model.developerStorage.state.report {
            return StorageFormatters.bytes(report.totalSize)
        }
        return nil
    }

    private var primaryFolderButtonTitle: String {
        switch model.selectedSection {
        case .developerStorage: "Add Projects Folder"
        case .aiModelsAndRuntimes: "Add Model Folder"
        default: "Scan a Folder"
        }
    }

    /// Folder changes wait for a batch that already snapshotted this analysis's folders.
    private var isPrimaryFolderButtonDisabled: Bool {
        switch model.selectedSection {
        case .developerStorage: model.isInScanEverything(.developerStorage)
        case .aiModelsAndRuntimes: model.isInScanEverything(.aiModelsAndRuntimes)
        default: false
        }
    }

    private var primaryFolderButtonHelp: String {
        switch model.selectedSection {
        case .developerStorage: "Choose a project or parent folder to include in developer storage analysis"
        case .aiModelsAndRuntimes: "Choose another folder to include in AI model analysis"
        default: "Choose a folder to inspect"
        }
    }

    private func removeSelectedFolder() {
        guard let path = activeLocationPath,
              let folder = model.sessionFolders.first(where: { $0.id == path }) else { return }
        model.removeSessionFolder(folder)
    }
}

private struct ScanEverythingControl: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let activities = model.activities

        if !activities.isEmpty {
            let cards = VStack(spacing: 8) {
                ForEach(activities) { activity in
                    ScanActivityCard(activity: activity)
                }
            }
            ViewThatFits(in: .vertical) {
                cards
                ScrollView { cards }
            }
        }

        HStack(spacing: 8) {
            Button {
                model.requestDiscScan()
            } label: {
                Label("Disc Scan", systemImage: "internaldrive.fill")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(!model.canRequestDiscScan)
            .help("Scan every mounted local disk")
            .accessibilityHint("Scans all mounted local disks")

            Button {
                model.requestAllAnalyses()
            } label: {
                Label("Analysis", systemImage: "chart.bar.xaxis")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(!model.canRequestAllAnalyses)
            .help("Run all storage analyses")
            .accessibilityHint("Runs AI Coding Tools, AI Models, and Developer Storage analyses")
        }

        if activities.isEmpty, let outcome = model.lastScanEverythingOutcome {
            Text(summaryText(outcome))
                .font(.caption2)
                .foregroundStyle(outcome.summary.failureCount == 0 ? theme.tertiaryText : theme.warning)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func summaryText(_ outcome: ScanEverythingOutcome) -> String {
        let summary = outcome.summary
        let duration = StorageFormatters.duration(summary.duration)
        return "\(outcome.scope.title): completed \(summary.completedCount) of \(summary.outcomes.count) "
            + "steps in \(duration)"
    }
}

private struct ScanActivityCard: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let activity: ScanActivity

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: activity.systemImage)
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text(activity.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button {
                    model.cancel(activity)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)
                .help("Cancel: \(activity.title)")
                .accessibilityLabel("Cancel: \(activity.title)")
            }

            Text(activity.status)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Group {
                if activity.isQueued {
                    ProgressView(value: 0)
                } else if let fraction = activity.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(theme.accent)

            HStack {
                Text(activity.isQueued ? "Queued" : activity.detail)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let startedAt = activity.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(StorageFormatters.duration(max(context.date.timeIntervalSince(startedAt), 0)))
                    }
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(theme.tertiaryText)

            if let location = activity.location, !location.isEmpty {
                Text(location)
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(11)
        .background(theme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(activity.currentPath ?? activity.status)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(activity.isQueued ? "\(activity.title), queued" : "\(activity.title) in progress")
        .accessibilityValue("\(activity.status), \(activity.detail)")
    }
}

private struct VolumeRow: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let volume: VolumeInfo
    let showsLocation: Bool
    let isSelected: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let hasCachedResult = model.cachedResult(for: volume) != nil

        VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: volume.isExternal ? "externaldrive.fill" : "internaldrive.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(volumeSubtitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isSelected ? theme.secondaryText : theme.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if model.isScanActive(on: volume) {
                        ProgressView()
                            .controlSize(.small)
                    } else if hasCachedResult {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.elevatedSurface)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [theme.accent, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(3, proxy.size.width * volume.usedFraction))
                    }
                }
                .frame(height: 4)
            }
            .padding(11)
            .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.selectionSurface : Color.clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.selectionBorder, lineWidth: 1)
                    }
                }
        }
        .onTapGesture { model.selectVolume(volume) }
        .contextMenu {
            if hasCachedResult {
                Button("View Existing Result") { model.viewCachedResult(at: volume.url) }
                Button("Rescan Disk") { model.scan(volume.url) }
                    .disabled(model.isScanActive(on: volume))
                Divider()
            } else {
                Button("Scan") { model.scan(volume.url) }
                    .disabled(model.isScanActive(on: volume))
                Divider()
            }
            Button("Show in Finder") {
                let node = FileNode(
                    url: volume.url,
                    name: volume.name,
                    size: volume.usedCapacity,
                    isDirectory: true,
                    isReadable: true,
                    children: []
                )
                model.showInFinder(node)
            }
        }
        .accessibilityLabel(
            "\(volume.name), \(StorageFormatters.percent(volume.usedFraction)) used"
                + (volume.isStartupVolume ? ", startup disk" : "")
                + (showsLocation ? ", mounted at \(volume.url.path)" : "")
                + (hasCachedResult ? ", session scan available" : "")
        )
        .accessibilityHint(hasCachedResult ? "Opens the saved scan immediately" : "Shows this disk overview")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selectVolume(volume) }
    }

    private var volumeSubtitle: String {
        let capacity = "\(StorageFormatters.bytes(volume.usedCapacity)) of \(StorageFormatters.bytes(volume.totalCapacity))"
        let startupLabel = volume.isStartupVolume ? "Startup disk" : nil
        let location = showsLocation ? volume.url.path : nil
        return ([startupLabel, capacity, location].compactMap { $0 }).joined(separator: " · ")
    }
}

private struct SessionFolderRow: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let folder: SessionFolder
    let isSelected: Bool

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let cachedResult = model.cachedResult(for: folder)
        let isScanning = model.isScanActive(at: folder.url)

        HStack(spacing: 3) {
            HStack(spacing: 9) {
                    StorageItemIconView(url: folder.url, isDirectory: true, size: 22) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .frame(width: 22)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)

                        Text(
                            cachedResult.map {
                                "\(StorageFormatters.bytes($0.root.size)) scanned"
                            } ?? folder.url.deletingLastPathComponent().path
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? theme.secondaryText : theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else if cachedResult != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                .padding(.leading, 9)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { model.selectSessionFolder(folder) }
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { model.selectSessionFolder(folder) }
            .frame(maxWidth: .infinity)

            Button {
                model.removeSessionFolder(folder)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(folder.name) from sidebar")
            .accessibilityLabel("Remove \(folder.name) from sidebar")
            .padding(.trailing, 4)
        }
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.selectionSurface : Color.clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.selectionBorder, lineWidth: 1)
                    }
                }
        }
        .contextMenu {
            if cachedResult != nil {
                Button("View Existing Result") { model.viewCachedResult(at: folder.url) }
                Button("Rescan Folder") { model.scan(folder.url) }
                    .disabled(isScanning)
            } else {
                Button("Scan Folder") { model.scan(folder.url) }
                    .disabled(isScanning)
            }
            Divider()
            Button("Show in Finder") {
                model.showInFinder(
                    FileNode(
                        url: folder.url,
                        name: folder.name,
                        size: cachedResult?.root.size ?? 0,
                        isDirectory: true,
                        isReadable: true,
                        children: []
                    )
                )
            }
            Button("Remove from Sidebar") {
                model.removeSessionFolder(folder)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
