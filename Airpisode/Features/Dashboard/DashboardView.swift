import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var justUpdated = false

    private var items: [UpcomingItem] { appState.library.upcomingReleases() }

/// "Date-only items with no known date floor in the Later bucket" is preserved from Upcoming;
/// these three stay exactly as before.

    private var today: [UpcomingItem] { items.filter { ($0.date ?? .distantPast) < Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400) && $0.date != nil } }
    private var thisWeek: [UpcomingItem] { items.filter { item in
        guard let date = item.date else { return false }
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        return date >= start && date < start.addingTimeInterval(6 * 86_400)
    } }
    private var later: [UpcomingItem] { items.filter { item in
        guard let date = item.date else { return true }
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(7 * 86_400)
        return date >= start
    } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let error = appState.lastRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                        .appear()
                }

                HStack(alignment: .firstTextBaseline) {
                    PageHeader(title: "To Watch",
                               subtitle: "What's coming up — and what already aired and is waiting for you")
                    Spacer()
                    if justUpdated {
                        Label("Updated just now", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }

                if !appState.unreadScheduleChanges.isEmpty {
                    ScheduleChangesCard(records: appState.unreadScheduleChanges)
                }

                if items.isEmpty
                    && appState.library.releasedUnwatchedEpisodes().isEmpty
                    && appState.library.releasedUnwatchedMovies().isEmpty {
                    emptyState
                } else {
                    // Aired-but-unwatched first (checkbox clears them), then what's still ahead.
                    HistorySection(
                        items: appState.library.releasedUnwatchedEpisodes(),
                        heading: "Episodes",
                        onMarkWatched: { item in
                            appState.setEpisodeWatched(true, episode: item.episode, titleID: item.title.id)
                        }
                    )
                    HistorySection(
                        items: appState.library.releasedUnwatchedMovies(),
                        heading: "Movies",
                        onMarkWatched: { item in
                            appState.setMovieWatched(true, titleID: item.title.id)
                        }
                    )
                    section("Today", today)
                    section("This Week", thisWeek)
                    section("Later", later)
                }
            }
            .padding(24)
            .padding(.bottom, DockBar.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.smooth, value: justUpdated)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("To Watch")
        .toolbar {
            Button {
                Task {
                    await appState.runFullRefresh()
                    justUpdated = true
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    justUpdated = false
                }
            } label: {
                if appState.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(appState.isRefreshing)
            .help("Refresh release dates")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Nothing to watch yet")
                .font(.headline)
            Text("Track a show or movie and its next release shows up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Find something to track", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .appear()
    }

    @ViewBuilder
    private func section(_ name: String, _ items: [UpcomingItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(.title3)
                    .fontWeight(.semibold)
                ForEach(items) { item in
                    DashboardRowView(item: item)
                        .hoverLift()
                }
            }
        }
    }
}
