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
    let airTimes: AirTimeProviding
    private let store: LibraryStore

    init(
        store: LibraryStore = LibraryStore(),
        tmdb: TMDBClientProtocol = TMDBClient(),
        notifications: NotificationScheduler = NotificationScheduler(client: SystemNotificationClient()),
        airTimes: AirTimeProviding = TVmazeClient()
    ) {
        self.store = store
        self.tmdb = tmdb
        self.notifications = notifications
        self.airTimes = airTimes
        // The UN delegate is a singleton slot: install this state so banner action taps
        // (Mark watched / Mute) reach the library mutations.
        AppDelegate.actionHandler = self
    }

    func loadLibrary() async {
        library = await store.load()
        // Move legacy show-level watches first, then backfill the diary from the final sets.
        let migratedWatched = library.migrateLegacyWatchedState()
        let migratedSchema = library.migrateSchemaIfNeeded()
        let pruned = library.pruneWatchLog()
        if migratedSchema || migratedWatched || pruned > 0 { save() }
        rescheduleAll()
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
        library.scheduleChanges.removeAll { $0.titleID == titleID }
        library.removeWatchRecords { $0.titleID == titleID }
        _ = library.pruneWatchLog()
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
        let now = Date()
        if watched {
            library.watchedEpisodes.formUnion(ids)
            for id in ids {
                upsertWatchRecord(
                    kind: .episode, titleID: titleID, itemID: id, watchedAt: now
                )
            }
            // Nothing left to alert about for episodes already watched.
            notifications.cancelAll(forTitle: titleID, keys: ids)
        } else {
            library.watchedEpisodes.subtract(ids)
            let removing = Set(ids)
            library.removeWatchRecords {
                $0.kind == .episode && removing.contains($0.itemID)
            }
        }
        _ = library.pruneWatchLog()
        // Reconciliation also handles the unwatched case: a returning episode can rejoin
        // the plan, while watched IDs disappear from it.
        rescheduleAll()
        save()
    }

    /// Marks a movie watched (or unwatched). Watched movies leave History.
    func setMovieWatched(_ watched: Bool, titleID: String) {
        if watched {
            library.watchedMovies.insert(titleID)
            upsertWatchRecord(
                kind: .movie, titleID: titleID, itemID: titleID, watchedAt: Date()
            )
        } else {
            library.watchedMovies.remove(titleID)
            library.removeWatchRecords {
                $0.kind == .movie && $0.itemID == titleID
            }
        }
        _ = library.pruneWatchLog()
        rescheduleAll()
        save()
    }

    /// One record per item. Re-marking refreshes the timestamp rather than duplicating.
    private func upsertWatchRecord(
        kind: WatchRecord.Kind,
        titleID: String,
        itemID: String,
        watchedAt: Date
    ) {
        library.upsertWatchRecord(
            kind: kind, titleID: titleID, itemID: itemID, watchedAt: watchedAt
        )
    }

    /// Mutes (or unmutes) a title's alerts. Muting cancels everything already scheduled for
    /// it; the title stays in the library and keeps feeding the To Watch page.
    func setAlertsMuted(_ muted: Bool, titleID: String) {
        guard let index = library.entries.firstIndex(where: { $0.id == titleID }) else { return }
        library.entries[index].alertsMuted = muted
        if muted {
            let episodes = library.episodes[titleID] ?? []
            let keys = episodes.map(\.id) + (library.movieReleases[titleID] ?? []).map(\.id)
            notifications.cancelAll(forTitle: titleID, keys: keys)
        }
        rescheduleAll()
        save()
    }

    /// Changes one show's pre-release lead time without touching the global setting.
    func setPreAlertOverride(_ override: AlertOverride, titleID: String) {
        guard let index = library.entries.firstIndex(where: { $0.id == titleID }) else { return }
        library.entries[index].preAlertOverride = override
        rescheduleAll()
        save()
    }

    // MARK: - Schedule changes

    var unreadScheduleChanges: [ScheduleChangeRecord] {
        library.scheduleChanges.filter { !$0.isRead }
    }

    func markScheduleChangesRead() {
        guard library.scheduleChanges.contains(where: { !$0.isRead }) else { return }
        for index in library.scheduleChanges.indices {
            library.scheduleChanges[index].isRead = true
        }
        save()
    }

    /// Pins (or unpins) a row to the top of its list. Display-only ordering — the entry keeps
    /// its `addedAt`, so the Recently added sort still reads its true age.
    func setPinned(_ pinned: Bool, titleID: String) {
        guard let index = library.entries.firstIndex(where: { $0.id == titleID }) else { return }
        library.entries[index].pinnedAt = pinned ? Date() : nil
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

    /// Fetches basic person data for the cast popover.
    func fetchPerson(tmdbID: Int) async -> TMDBPersonDetail? {
        try? await tmdb.person(tmdbID: tmdbID)
    }

    /// The title's best YouTube trailer URL, for the detail hero's Trailer button.
    func fetchTrailer(tmdbID: Int, mediaType: MediaType) async -> URL? {
        let videos = (try? await tmdb.videos(mediaType: mediaType, tmdbID: tmdbID)) ?? []
        return videos.youTubeTrailer?.youTubeURL
    }

    /// Fetches the region's streaming offers ("Where to watch"). The region is an explicit
    /// parameter so tests never read this Mac's config; the view passes the current setting.
    func fetchWatchProviders(mediaType: MediaType, tmdbID: Int, region: String) async -> TMDBRegionProviders? {
        let response = try? await tmdb.watchProviders(mediaType: mediaType, tmdbID: tmdbID)
        return response?.region(region)
    }

    /// Refreshes tracked titles through the ReleaseEngine and reschedules alerts.
    /// `force` bypasses the staleness TTL so a manual refresh always hits the network.
    /// `animated` keeps the minimum-visible spinner for user-initiated refreshes; background
    /// passes use `false` so an idle hour never flashes the window's spinner.
    /// Returns how many tracked titles could not be refreshed (an unreachable network leaves
    /// their previous `lastRefreshed` in place), so the background sweep can tell a fully
    /// successful pass from an offline one. The spinner-hold sleep only runs when `animated`.
    @discardableResult
    func runFullRefresh(force: Bool = true, animated: Bool = true) async -> Int {
        guard !isRefreshing else { return 0 }
        isRefreshing = true
        let started = Date()

        let engine = ReleaseEngine(client: tmdb, airTimes: airTimes)
        var snapshot = library
        // A title with a prior successful refresh is the only one whose diff is meaningful.
        // The first load of a newly added show sees its whole season as "new".
        let previouslyRefreshed = Set(snapshot.entries.compactMap { entry in
            snapshot.titles[entry.id]?.lastRefreshed == nil ? nil : entry.id
        })
        let changes = await engine.refreshIfNeeded(library: &snapshot, now: .now, force: force)
        library = snapshot
        recordScheduleChanges(changes, previouslyRefreshed: previouslyRefreshed)
        try? await store.save(library)
        // A title still carrying a pre-sweep `lastRefreshed` was not re-fetched (offline pass).
        // Titles without loaded data are ignored so a data-less entry can never block forever.
        let failed = snapshot.entries.filter { entry in
            guard let title = snapshot.titles[entry.id] else { return false }
            return (title.lastRefreshed ?? .distantPast) < started
        }.count
        lastRefreshError = failed > 0
            ? "Couldn't refresh \(failed) title\(failed == 1 ? "" : "s"). Will retry automatically."
            : nil
        rescheduleAll()

        // Keep the spinner visible long enough to read even when nothing was stale.
        let elapsed = Date().timeIntervalSince(started)
        if animated, elapsed < 0.6 {
            try? await Task.sleep(nanoseconds: UInt64((0.6 - elapsed) * 1_000_000_000))
        }
        isRefreshing = false
        return failed
    }

    func refreshTitle(_ titleID: String) async {
        guard let entry = library.entries.first(where: { $0.id == titleID }) else { return }
        let now = Date()
        let hadRefreshed = library.titles[titleID]?.lastRefreshed != nil
        let oldEpisodes = library.episodes[titleID] ?? []
        let oldReleases = library.movieReleases[titleID] ?? []
        do {
            var changes: [ReleaseChange] = []
            switch entry.mediaType {
            case .tv:
                let detail = try await tmdb.tvDetail(id: entry.tmdbID)
                var title = TMDBMapper.title(from: detail)
                var episodes: [Episode] = []
                for season in detail.seasons where season.seasonNumber > 0 {
                    let seasonData = try await tmdb.season(tvID: entry.tmdbID, season: season.seasonNumber)
                    episodes += TMDBMapper.episodes(seasonData, tvID: entry.tmdbID)
                }
                episodes = await AirTimeEnricher.enrich(
                    episodes,
                    previous: oldEpisodes,
                    detail: detail,
                    provider: airTimes,
                    now: now
                )
                changes = ReleaseEngine.diff(
                    old: oldEpisodes, new: episodes, titleID: titleID,
                    lastRefreshed: library.titles[titleID]?.lastRefreshed, now: now,
                    id: { $0.id }, date: { $0.airDate }, hasTime: { _ in false }
                )
                title.lastRefreshed = now
                library.titles[titleID] = title
                library.episodes[titleID] = episodes
            case .movie:
                let detail = try await tmdb.movieDetail(id: entry.tmdbID)
                var title = TMDBMapper.title(from: detail)
                let releases = try await tmdb.movieReleaseDates(id: entry.tmdbID)
                let region = ConfigStore.defaultRegion
                let mapped = TMDBMapper.movieReleases(releases, movieID: entry.tmdbID, region: region)
                changes = ReleaseEngine.diff(
                    old: oldReleases, new: mapped, titleID: titleID,
                    lastRefreshed: library.titles[titleID]?.lastRefreshed, now: now,
                    id: { $0.id }, date: { $0.date }, hasTime: { $0.hasTime }
                )
                title.lastRefreshed = now
                library.titles[titleID] = title
                library.movieReleases[titleID] = mapped
            }
            recordScheduleChanges(
                changes,
                previouslyRefreshed: hadRefreshed ? [titleID] : []
            )
            lastRefreshError = nil
            try? await store.save(library)
            rescheduleAll()
        } catch {
            lastRefreshError = "Couldn't refresh \(library.titles[titleID]?.name ?? titleID): \(error.localizedDescription)"
        }
    }

    // MARK: - Launch refresh

    private var didRefreshOnLaunch = false

    /// One forced pass when the window first appears, so launching the app actually updates
    /// data instead of waiting for the hourly heartbeat. Skips a relaunch within ten minutes
    /// so quitting and reopening does not hammer TMDB. Returns without doing anything when
    /// the caller already knows there is no API key.
    func refreshOnLaunch(now: Date = .now, in calendar: Calendar = .current) async {
        guard !didRefreshOnLaunch else { return }
        didRefreshOnLaunch = true

        // Only skip when every tracked title was refreshed moments ago. One fresh title must
        // not hide stale siblings after a long time away.
        let allFresh = library.entries.allSatisfy { entry in
            guard let refreshed = library.titles[entry.id]?.lastRefreshed else { return false }
            return now.timeIntervalSince(refreshed) < 600
        }
        if allFresh && !library.entries.isEmpty {
            // Recent enough. Stamp the morning slot so the hourly ticker does not immediately
            // repeat a sweep that just happened moments before launch.
            if let slot = dailySweepSlot(for: now, in: calendar), now >= slot {
                lastDailySweepSlot = slot
            }
            return
        }

        let failed = await runFullRefresh(force: true, animated: false)
        if failed == 0, let slot = dailySweepSlot(for: now, in: calendar), now >= slot {
            lastDailySweepSlot = slot
        }
    }

    // MARK: - Background refresh

    private var backgroundRefreshTicker: Timer?
    /// Bumped once per heartbeat so tests can observe the ticker without network.
    private(set) var backgroundRefreshTicks = 0

    /// Local hour the once-per-day sweep anchors at — early enough that TMDB already knows
    /// today's air times, and always evaluated in the user's own time zone via their calendar.
    static let dailySweepStartHour = 6

    /// The morning slot the last daily sweep covered (nil until one has run).
    var lastDailySweepSlot: Date?

    /// The process now outlives its window, and this ticker keeps the To Watch page fresh with
    /// at most ONE network sweep per local day: shortly after the 6 AM anchor in the user's own
    /// time zone, every tracked title is re-fetched (force) and its notifications re-scheduled,
    /// so release dates and just-aired entries stay current without hammering TMDB. Launching
    /// after the anchor on a day with no sweep yet sweeps right away. A repeating Timer cannot
    /// be trusted across sleep/wake, so the heartbeat only tags due-ness; each heartbeat also
    /// counts in `backgroundRefreshTicks`. Safe to repeat: the guard makes the first call the
    /// only one that schedules.
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

    /// The 6 AM (local) morning slot that contains `date`.
    func dailySweepSlot(for date: Date, in calendar: Calendar = .current) -> Date? {
        calendar.date(
            bySettingHour: Self.dailySweepStartHour, minute: 0, second: 0,
            of: date, matchingPolicy: .nextTime
        )
    }

    /// Due when the current morning slot has passed but no sweep has run for it yet.
    func isDailySweepDue(now: Date, in calendar: Calendar = .current) -> Bool {
        guard let slot = dailySweepSlot(for: now, in: calendar) else { return false }
        guard now >= slot else { return false } // hours before the morning anchor: not yet
        return slot != lastDailySweepSlot
    }

    func tickBackgroundRefresh(now: Date = .now, in calendar: Calendar = .current) async {
        backgroundRefreshTicks += 1
        // A user refresh in flight could collide with the sweep's choices; skip this heartbeat
        // entirely — the next hour covers it.
        guard !isRefreshing, isDailySweepDue(now: now, in: calendar) else { return }
        let failed = await runFullRefresh(force: true, animated: false)
        // Stamp the slot only on a fully successful sweep. When the network was unreachable the
        // slot stays unstamped, and the next hourly heartbeat retries automatically — a 6 AM
        // attempt made while offline lands as soon as connectivity returns (e.g. 8 AM online).
        if failed == 0 {
            lastDailySweepSlot = dailySweepSlot(for: now, in: calendar)
        }
    }

    // MARK: - Notifications

    func updateNotificationPreferences(_ mutate: (inout NotificationPreferences) -> Void) {
        mutate(&library.preferences)
        save()
        rescheduleAll()
    }

    /// Reconciles every alert in one pass. Using the whole library is what lets the planner
    /// see the 64-request budget and keep the soonest alerts instead of whichever title was
    /// scheduled last.
    private func rescheduleAll() {
        let snapshot = library
        Task { await notifications.apply(library: snapshot) }
    }

    func notificationDiagnostics(now: Date = .now) async -> NotificationDiagnosticsReport {
        let authorization = await notifications.client.authorizationStatus()
        let pending = await notifications.client.pendingAlerts()
        return NotificationDiagnostics.report(
            library: library,
            authorization: authorization,
            pending: pending,
            now: now
        )
    }

    func sendTestAlert() async {
        let poster = library.entries.compactMap { library.titles[$0.id]?.posterPath }.first
        await notifications.sendTestAlert(posterPath: poster)
    }

    private func recordScheduleChanges(
        _ changes: [ReleaseChange],
        previouslyRefreshed: Set<String>,
        now: Date = .now
    ) {
        let records = ScheduleChangeRecorder.records(
            from: changes,
            library: library,
            previouslyRefreshed: previouslyRefreshed,
            now: now
        )
        guard !records.isEmpty else { return }
        library.scheduleChanges = ScheduleChangeRecorder.merge(records, into: library.scheduleChanges)
        if library.preferences.notifyScheduleChanges {
            Task { await notifications.notifyScheduleChanges(records, now: now) }
        }
    }

    private func save() {
        let snapshot = library
        Task { try? await store.save(snapshot) }
    }
}

extension AppState: NotificationActionHandling {
    /// Routes banner action taps: episode notifications mark that episode watched, movie
    /// notifications mark the movie watched, and every category offers a one-tap mute.
    @MainActor
    func handleNotificationAction(identifier: String, titleID: String, kind: String, key: String?) {
        switch identifier {
        case NotificationScheduler.markWatchedAction:
            if kind == "episode" {
                guard let key,
                      let episode = library.episodes[titleID]?.first(where: { $0.id == key })
                else { break }
                setEpisodeWatched(true, episode: episode, titleID: titleID)
            } else if kind == "movie" {
                setMovieWatched(true, titleID: titleID)
            }
        case NotificationScheduler.muteTitleAction:
            setAlertsMuted(true, titleID: titleID)
        default:
            break
        }
    }
}
