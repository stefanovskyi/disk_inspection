import SwiftUI

struct NavigationHeader: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    let node: FileNode

    var body: some View {
        let theme = SpaceTheme(colorScheme: colorScheme)

        HStack(spacing: 10) {
            Button {
                model.navigateBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canNavigateBack ? theme.primaryText : theme.tertiaryText.opacity(0.45))
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(!model.canNavigateBack)
            .accessibilityLabel("Back")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(model.navigationPath.enumerated()), id: \.element.id) { index, breadcrumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
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
                            .font(.system(size: 12, weight: index == model.navigationPath.count - 1 ? .semibold : .medium))
                            .foregroundStyle(index == model.navigationPath.count - 1 ? theme.primaryText : theme.secondaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(index == model.navigationPath.count - 1 ? theme.elevatedSurface : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Go to \(breadcrumb.name)")
                    }
                }
            }

            Spacer(minLength: 12)

            if let result = model.result {
                HStack(spacing: 12) {
                    if result.unreadableItems > 0 {
                        Button {
                            model.openFullDiskAccessSettings()
                        } label: {
                            Label("\(result.unreadableItems) protected", systemImage: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.warning)
                        .help("Open Full Disk Access settings")
                    }

                    Text("\(result.itemsScanned.formatted()) items · \(StorageFormatters.duration(result.duration))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            Button {
                model.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help("Rescan")
            .accessibilityLabel("Rescan")
        }
        .padding(.top, 35)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
