import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    private var items: [UpcomingItem] { appState.library.upcomingReleases() }
    private var airedEpisodes: [ReleasedEpisode] { appState.library.releasedUnwatchedEpisodes() }
    private var airedMovies: [ReleasedMovie] { appState.library.releasedUnwatchedMovies() }

    private var today: [UpcomingItem] {
        items.filter {
            guard let date = $0.date else { return false }
            return date < Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        }
    }

    private var thisWeek: [UpcomingItem] {
        items.filter { item in
            guard let date = item.date else { return false }
            let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
            return date >= start && date < start.addingTimeInterval(6 * 86_400)
        }
    }

    private var later: [UpcomingItem] {
        items.filter { item in
            guard let date = item.date else { return true }
            let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(7 * 86_400)
            return date >= start
        }
    }

    private var isEmpty: Bool {
        items.isEmpty && airedEpisodes.isEmpty && airedMovies.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header

                if let error = appState.lastRefreshError {
                    InlineBanner(message: error, tone: .warning, actionTitle: "Try Again") {
                        Task { await appState.runFullRefresh() }
                    }
                }

                if !appState.unreadScheduleChanges.isEmpty {
                    ScheduleChangesCard(records: appState.unreadScheduleChanges)
                }

                if isEmpty {
                    EmptyState(
                        systemImage: "checklist",
                        title: "Nothing to watch yet",
                        message: "Track a show or movie and its next release appears here, with what is already waiting for you.",
                        actionTitle: "Find something to track"
                    ) {
                        appState.selectedSection = .discover
                    }
                } else {
                    // Waiting first: it is the only part that asks for an action.
                    if !airedEpisodes.isEmpty || !airedMovies.isEmpty {
                        HistorySection(
                            items: airedEpisodes,
                            heading: "Episodes waiting",
                            onMarkWatched: { item in
                                appState.setEpisodeWatched(true, episode: item.episode, titleID: item.title.id)
                            }
                        )
                        HistorySection(
                            items: airedMovies,
                            heading: "Movies waiting",
                            onMarkWatched: { item in
                                appState.setMovieWatched(true, titleID: item.title.id)
                            }
                        )
                    }

                    section("Today", today)
                    section("This Week", thisWeek)
                    section("Later", later)
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
            .animation(Motion.smooth, value: appState.unreadScheduleChanges.count)
        }
        .screenBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await appState.runFullRefresh() }
                } label: {
                    if appState.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(appState.isRefreshing)
                .help("Refresh release dates (⌘R)")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next up")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(DateText.freshness(appState.lastRefreshAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let waiting = airedEpisodes.count + airedMovies.count
        let ahead = today.count + thisWeek.count
        switch (waiting, ahead) {
        case (0, 0): return "Nothing scheduled. Add a show or movie to follow its releases."
        case (0, _): return "\(ahead) release\(ahead == 1 ? "" : "s") in the next seven days."
        case (_, 0): return "\(waiting) item\(waiting == 1 ? "" : "s") already aired and waiting for you."
        default: return "\(waiting) waiting · \(ahead) in the next seven days."
        }
    }

    @ViewBuilder
    private func section(_ name: String, _ items: [UpcomingItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: name, count: items.count)
                VStack(spacing: Theme.Space.s) {
                    ForEach(items) { item in
                        DashboardRowView(item: item)
                    }
                }
            }
        }
    }
}
