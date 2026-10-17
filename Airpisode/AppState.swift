import SwiftUI

enum Secrets {
    /// The user's TMDB API key: one entered in Settings wins, otherwise the build-time
    /// Info.plist value is a developer fallback. A distributed build ships without a baked key,
    /// so the app asks for one on first launch. Stored in the app's own config file, not UserDefaults.
    static var tmdbKey: String {
        let stored = ConfigStore.tmdbAPIKey
        if !stored.isEmpty { return stored }
        let baked = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? ""
        return baked.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasKey: Bool { !tmdbKey.isEmpty }

    static func setTMDBKey(_ value: String) {
        ConfigStore.setTMDBAPIKey(value)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var library = Library()
    @Published var lastRefreshError: String?
    @Published var isRefreshing = false
    @Published var selectedSection: AppSection? = .dashboard

    let tmdb: TMDBClientProtocol
    let notifications: NotificationScheduler
    private let store: LibraryStore

    init(
        store: LibraryStore = LibraryStore(),
        tmdb: TMDBClientProtocol = TMDBClient(),
        notifications: NotificationScheduler = NotificationScheduler(client: SystemNotificationClient())
    ) {
        self.store = store
        self.tmdb = tmdb
        self.notifications = notifications
    }

    func loadLibrary() async {
        library = await store.load()
        if library.migrateLegacyWatchedState() { save() }
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
        let episodes = library.episodes[titleID] ?? []
        let keys = episodes.map(\.id) + (library.movieReleases[titleID] ?? []).map(\.id)
        notifications.cancelAll(forTitle: titleID, keys: keys)
        library.entries.removeAll { $0.id == titleID }
        library.titles.removeValue(forKey: titleID)
        library.episodes.removeValue(forKey: titleID)
        library.movieReleases.removeValue(forKey: titleID)
        library.watchedShows.remove(titleID)
        library.watchedMovies.remove(titleID)
        library.watchedEpisodes.subtract(episodes.map(\.id))
        save()
    }

    // MARK: - Watched state

    /// Marks a released episode watched (or unwatched). Watched episodes leave History, and
    /// marking one cancels the alerts that were still scheduled for it.
    func setEpisodeWatched(_ watched: Bool, episode: Episode, titleID: String) {
        setEpisodesWatched(watched, episodes: [episode], titleID: titleID)
    }

    /// Bulk version of `setEpisodeWatched`, used by the season-level actions in a show's
    /// episode list.
    func setEpisodesWatched(_ watched: Bool, episodes: [Episode], titleID: String) {
        guard !episodes.isEmpty else { return }
        let ids = episodes.map(\.id)
        if watched {
            library.watchedEpisodes.formUnion(ids)
            // Nothing left to alert about for episodes already watched.
            notifications.cancelAll(forTitle: titleID, keys: ids)
        } else {
            library.watchedEpisodes.subtract(ids)
            // Un-watching can bring an episode back into the alert schedule.
            reschedule(titleID: titleID)
        }
        save()
    }

    /// Marks a movie watched (or unwatched). Watched movies leave History.
    func setMovieWatched(_ watched: Bool, titleID: String) {
        if watched {
            library.watchedMovies.insert(titleID)
        } else {
            library.watchedMovies.remove(titleID)
        }
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

    /// Fetches a title's cast without adding it to the library.
    func fetchCredits(tmdbID: Int, mediaType: MediaType) async -> [TMDBCastMember] {
        (try? await tmdb.credits(mediaType: mediaType, tmdbID: tmdbID)) ?? []
    }

    /// Refreshes tracked titles through the ReleaseEngine and reschedules alerts.
    /// `force` bypasses the staleness TTL so a manual refresh always hits the network.
    /// `animated` keeps the minimum-visible spinner for user-initiated refreshes; background
    /// passes use `false` so an idle hour never flashes the window's spinner.
    func runFullRefresh(force: Bool = true, animated: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let started = Date()

        let engine = ReleaseEngine(client: tmdb)
        var snapshot = library
        _ = await engine.refreshIfNeeded(library: &snapshot, now: .now, force: force)
        library = snapshot
        try? await store.save(library)
        let failed = snapshot.entries.filter { snapshot.titles[$0.id]?.lastRefreshed == nil }.count
        lastRefreshError = failed > 0
            ? "Couldn't refresh \(failed) title\(failed == 1 ? "" : "s"). Will retry automatically."
            : nil
        for entry in snapshot.entries {
            reschedule(titleID: entry.id)
        }

        // Keep the spinner visible long enough to read even when nothing was stale.
        let elapsed = Date().timeIntervalSince(started)
        if animated, elapsed < 0.6 {
            try? await Task.sleep(nanoseconds: UInt64((0.6 - elapsed) * 1_000_000_000))
        }
        isRefreshing = false
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
                let region = ConfigStore.defaultRegion
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

    // MARK: - Background refresh

    private var backgroundRefreshTicker: Timer?
    /// Bumped once per background pass so tests can observe the ticker without network.
    private(set) var backgroundRefreshTicks = 0

    /// The process now outlives its window, and these passes are what keep alerts accurate while
    /// it does: each pass refreshes only titles whose staleness TTL elapsed (6h inside 14 days
    /// of an airing, 24h inside 60 days) and re-schedules their notifications, so every tracked
    /// title still contacts TMDB at least once a day. The timer lives on AppState, not on a
    /// view, so ticks keep firing while the window is closed. Safe to repeat: the guard makes
    /// the first call the only one that schedules.
    func startBackgroundRefresh(every: TimeInterval = 3_600) {
        guard backgroundRefreshTicker == nil else { return }
        let ticker = Timer(timeInterval: every, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tickBackgroundRefresh() }
        }
        backgroundRefreshTicker = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }

    func isBackgroundRefreshRunning() -> Bool {
        backgroundRefreshTicker != nil
    }

    func stopBackgroundRefresh() {
        backgroundRefreshTicker?.invalidate()
        backgroundRefreshTicker = nil
    }

    private func tickBackgroundRefresh() async {
        backgroundRefreshTicks += 1
        await runFullRefresh(force: false, animated: false)
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
