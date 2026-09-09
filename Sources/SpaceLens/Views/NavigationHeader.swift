import SwiftUI

struct NavigationHeader: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let node: FileNode

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)
        let breadcrumbs = model.navigationPath.isEmpty ? [node] : model.navigationPath

        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(breadcrumbs.enumerated()), id: \.element.id) { index, breadcrumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(theme.tertiaryText)
                                .accessibilityHidden(true)
                        }

                        Button {
                            model.navigate(toBreadcrumbAt: index)
                        } label: {
                            HStack(spacing: 6) {
                                if index == 0 {
                                    Image(systemName: "internaldrive")
                                }
                                Text(breadcrumb.name)
                                    .lineLimit(1)
                            }
                            .font(.callout.weight(index == breadcrumbs.count - 1 ? .semibold : .medium))
                            .foregroundStyle(index == breadcrumbs.count - 1 ? theme.primaryText : theme.secondaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(index == breadcrumbs.count - 1 ? theme.elevatedSurface : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to \(breadcrumb.name)")
                    }
                }
            }

            Spacer(minLength: 12)

            if model.isScanning {
                Label("Updating", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            } else if let result = model.result {
                HStack(spacing: 12) {
                    if result.unreadableItems > 0 {
                        Button {
                            model.openFullDiskAccessSettings()
                        } label: {
                            Label("\(result.unreadableItems) protected", systemImage: "lock.fill")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.warning)
                        .help("Open Full Disk Access settings")
                    }

                    Text("\(result.itemsScanned.formatted()) items · \(StorageFormatters.duration(result.duration))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.tertiaryText)
                }
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
        }
    }
}
