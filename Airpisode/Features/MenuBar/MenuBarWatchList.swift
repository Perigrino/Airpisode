import SwiftUI

/// Menu-bar popover: the next few To Watch items with one-tap Mark watched, plus quick
/// Open / Refresh actions. Shares the library state with the main window and reuses the
/// app's design language in a compact form.
struct MenuBarWatchList: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let items = appState.library.upcomingReleases()
            .filter { !appState.library.isWatchedMovie($0.title.id) }

        return VStack(alignment: .leading, spacing: 4) {
            if items.isEmpty {
                emptyState
            } else {
                ForEach(items.prefix(5)) { item in
                    row(item)
                }
            }

            Divider().padding(.vertical, 2)
            footer

            if let error = appState.lastRefreshError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    // MARK: - Rows

    private func row(_ item: UpcomingItem) -> some View {
        HStack(spacing: 10) {
            PosterImage(path: item.title.posterPath, size: "w92", width: 40, height: 60, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            markButton(item)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { openToWatch() }
    }

    private func subtitle(for item: UpcomingItem) -> String {
        guard let date = item.date else { return item.label }
        return "\(item.label) · \(Self.relativeText(date))"
    }

    /// One-tap clearing of the To Watch row. Episode items only offer a mark when the
    /// actual episode is fetched (nextAiring-only rows have nothing to mark yet).
    @ViewBuilder
    private func markButton(_ item: UpcomingItem) -> some View {
        switch item.title.mediaType {
        case .movie:
            Button {
                withAnimation(Motion.quick) { appState.setMovieWatched(true, titleID: item.title.id) }
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help("Mark watched")
        case .tv:
            if let episode = appState.library.nextEpisode(forTitle: item.title.id) {
                Button {
                    withAnimation(Motion.quick) {
                        appState.setEpisodeWatched(true, episode: episode, titleID: item.title.id)
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Mark watched")
            } else {
                EmptyView()
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text("Nothing coming up — you're all caught up")
                .font(.callout)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(action: openToWatch) {
                Label("Open Airpisode", systemImage: "arrow.up.forward")
            }
            Spacer()
            Button {
                Task { await appState.runFullRefresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.plain)
        .font(.callout)
    }

    /// Opens the main window on the To Watch page — the same path the dock icon uses, so
    /// a hidden window comes back instead of a second one appearing.
    private func openToWatch() {
        appState.selectedSection = .dashboard
        BackgroundCloseIntercept.bringMainWindowBackIfNeeded()
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func relativeText(_ date: Date) -> String {
        if date <= Date.now { return "out now" }
        return relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}
