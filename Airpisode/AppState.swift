import SwiftUI

enum Secrets {
    static var tmdbKey: String {
        Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? ""
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var library = Library()
    @Published var lastRefreshError: String?

    let tmdb: TMDBClientProtocol
    let notifications: NotificationScheduler
    private let store: LibraryStore

    init(
        store: LibraryStore = LibraryStore(),
        tmdb: TMDBClientProtocol = TMDBClient(apiKey: Secrets.tmdbKey),
        notifications: NotificationScheduler = NotificationScheduler(client: SystemNotificationClient())
    ) {
        self.store = store
        self.tmdb = tmdb
        self.notifications = notifications
    }

    func loadLibrary() async {
        library = await store.load()
        for entry in library.entries {
            reschedule(titleID: entry.id)
        }
    }

    // MARK: - Library mutations

    func addToLibrary(_ title: Title) {
        guard !library.entries.contains(where: { $0.id == title.id }) else { return }
        library.titles[title.id] = title
        library.entries.append(
            WatchlistEntry(tmdbID: title.tmdbID, mediaType: title.mediaType, addedAt: Date(), isTrackingEnabled: true)
        )
        save()
    }

    func removeFromLibrary(_ titleID: String) {
        let keys = (library.episodes[titleID] ?? []).map(\.id) + (library.movieReleases[titleID] ?? []).map(\.id)
        notifications.cancelAll(forTitle: titleID, keys: keys)
        library.entries.removeAll { $0.id == titleID }
        library.titles.removeValue(forKey: titleID)
        library.episodes.removeValue(forKey: titleID)
        library.movieReleases.removeValue(forKey: titleID)
        library.watchedShows.remove(titleID)
        library.watchedMovies.remove(titleID)
        save()
    }

    // MARK: - Refresh

    /// Fetches a title's metadata without adding it to the library (used by the detail page before "Add").
    func fetchPreviewTitle(tmdbID: Int, mediaType: MediaType) async -> Title? {
        do {
            switch mediaType {
            case .tv:
                return TMDBMapper.title(from: try await tmdb.tvDetail(id: tmdbID))
            case .movie:
                return TMDBMapper.title(from: try await tmdb.movieDetail(id: tmdbID))
            }
        } catch {
            return nil
        }
    }

    /// Refreshes every tracked title through the ReleaseEngine (staleness-tiered) and reschedules alerts.
    func runFullRefresh() async {
        let engine = ReleaseEngine(client: tmdb)
        var snapshot = library
        _ = await engine.refreshIfNeeded(library: &snapshot, now: .now)
        library = snapshot
        try? await store.save(library)
        let failed = snapshot.entries.filter { snapshot.titles[$0.id]?.lastRefreshed == nil }.count
        lastRefreshError = failed > 0
            ? "Couldn't refresh \(failed) title\(failed == 1 ? "" : "s"). Will retry automatically."
            : nil
        for entry in snapshot.entries {
            reschedule(titleID: entry.id)
        }
    }

    func refreshTitle(_ titleID: String) async {
        guard let entry = library.entries.first(where: { $0.id == titleID }) else { return }
        do {
            switch entry.mediaType {
            case .tv:
                let detail = try await tmdb.tvDetail(id: entry.tmdbID)
                var title = TMDBMapper.title(from: detail)
                var episodes: [Episode] = []
                for season in detail.seasons where season.seasonNumber > 0 {
                    let seasonData = try await tmdb.season(tvID: entry.tmdbID, season: season.seasonNumber)
                    episodes += TMDBMapper.episodes(seasonData, tvID: entry.tmdbID)
                }
                title.lastRefreshed = Date()
                library.titles[titleID] = title
                library.episodes[titleID] = episodes
            case .movie:
                let detail = try await tmdb.movieDetail(id: entry.tmdbID)
                var title = TMDBMapper.title(from: detail)
                let releases = try await tmdb.movieReleaseDates(id: entry.tmdbID)
                let region = UserDefaults.standard.string(forKey: "defaultRegion") ?? "US"
                title.lastRefreshed = Date()
                library.titles[titleID] = title
                library.movieReleases[titleID] = TMDBMapper.movieReleases(releases, movieID: entry.tmdbID, region: region)
            }
            lastRefreshError = nil
            try? await store.save(library)
            reschedule(titleID: titleID)
        } catch {
            lastRefreshError = "Couldn't refresh \(library.titles[titleID]?.name ?? titleID): \(error.localizedDescription)"
        }
    }

    // MARK: - Notifications

    func updateNotificationPreferences(_ mutate: (inout NotificationPreferences) -> Void) {
        mutate(&library.preferences)
        save()
        for entry in library.entries {
            reschedule(titleID: entry.id)
        }
    }

    private func reschedule(titleID: String) {
        guard let title = library.titles[titleID] else { return }
        let episodes = library.episodes[titleID] ?? []
        let releases = library.movieReleases[titleID] ?? []
        let keys = episodes.map(\.id) + releases.map(\.id)
        notifications.cancelAll(forTitle: titleID, keys: keys)
        Task {
            await notifications.schedule(for: title, episodes: episodes, movieReleases: releases, prefs: library.preferences)
        }
    }

    private func save() {
        let snapshot = library
        Task { try? await store.save(snapshot) }
    }
}
