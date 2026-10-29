import SwiftUI

/// Menu-bar popover: the next few To Watch items with one-tap Mark watched, plus quick
/// Open / Refresh actions. Shares the library state with the main window and reuses the
/// app's design language in a compact form.
struct MenuBarWatchList: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let items = appState.library.upcomingReleases()
            .filter { !appState.library.isWatchedMovie($0.title.id) }

        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if items.isEmpty {
                emptyState
            } else {
                ForEach(items.prefix(5)) { item in
                    row(item)
                    if item.id != items.prefix(5).last?.id {
                        Divider()
                    }
                }
            }

            Divider().padding(.vertical, Theme.Space.xs)
            footer

            if let error = appState.lastRefreshError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.Space.m)
        .frame(width: 300)
        .tint(Theme.accentFill)
    }

    // MARK: - Rows

    private func row(_ item: UpcomingItem) -> some View {
        HStack(spacing: Theme.Space.s) {
            PosterImage(path: item.title.posterPath, size: "w92", width: 40, height: 60, cornerRadius: Theme.Radius.s)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            markButton(item)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { openToWatch() }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(for item: UpcomingItem) -> String {
        guard let date = item.date else { return item.label }
        let when = DateText.upcoming(date, includeTime: item.isTimed)
        if item.title.mediaType == .movie {
            return "Releases \(when)"
        }
        return "\(item.label) · \(when)"
    }

    /// One-tap clearing of the To Watch row. Episode items only offer a mark when the
    /// actual episode is fetched (nextAiring-only rows have nothing to mark yet).
    @ViewBuilder
    private func markButton(_ item: UpcomingItem) -> some View {
        switch item.title.mediaType {
        case .movie:
            markWatchedButton(titleID: item.title.id, help: "Mark watched") {
                appState.setMovieWatched(true, titleID: item.title.id)
            }
        case .tv:
            if let episode = appState.library.nextEpisode(forTitle: item.title.id) {
                markWatchedButton(titleID: item.title.id, help: "Mark watched") {
                    appState.setEpisodeWatched(true, episode: episode, titleID: item.title.id)
                }
            } else {
                EmptyView()
            }
        }
    }

    private func markWatchedButton(titleID: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.quick) { action() }
        } label: {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("Mark watched")
    }

    private var emptyState: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "checklist")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Nothing coming up — you're all caught up")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Space.m)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.m) {
            Button(action: openToWatch) {
                Label("Open Airpisode", systemImage: "arrow.up.forward")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button {
                Task { await appState.runFullRefresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(appState.isRefreshing)
        }
        .controlSize(.small)
    }

    /// Opens the main window on the To Watch page, so a hidden or closed window comes back
    /// instead of a second one appearing.
    private func openToWatch() {
        appState.selectedSection = .dashboard
        if !AppDelegate.showMainWindow() {
            openWindow(id: "main")
        }
    }
}
