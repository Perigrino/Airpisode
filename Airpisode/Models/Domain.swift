import Foundation

enum MediaType: String, Codable {
    case tv, movie
}

enum ReleaseKind: String, Codable {
    case theatrical, digital, physical, tv
}

struct SeasonSummary: Codable, Hashable {
    let seasonNumber: Int
    let episodeCount: Int
    let airDate: Date?
}

struct Title: Codable, Identifiable, Hashable {
    var id: String { "\(mediaType.rawValue)-\(tmdbID)" }
    let tmdbID: Int
    let mediaType: MediaType
    var name: String
    var overview: String
    var posterPath: String?
    var firstAirDate: Date?
    var tvStatus: String?
    var seasons: [SeasonSummary]
    var lastRefreshed: Date?
    /// TMDB's cross-show "next episode to air" — can be a future season's premiere even
    /// when that season's episodes aren't fetched yet. nil when TMDB knows nothing new.
    var nextAiring: Episode? = nil
}

struct Episode: Codable, Identifiable, Hashable {
    var id: String { "\(tmdbID)-s\(seasonNumber)e\(episodeNumber)" }
    let tmdbID: Int
    let seasonNumber: Int
    let episodeNumber: Int
    var name: String
    var overview: String?
    var airDate: Date?
    /// Exact broadcast instant from TVmaze when known. `airDate` stays the date-only
    /// TMDB value, used for display and release diffing.
    var airTimestamp: Date? = nil
    var stillPath: String?
}

struct MovieRelease: Codable, Identifiable, Hashable {
    var id: String { "\(tmdbID)-\(kind.rawValue)-\(region)" }
    let tmdbID: Int
    let kind: ReleaseKind
    let region: String
    var date: Date?
    var hasTime: Bool  // false → date-only, never invent a time
}

/// Per-show override for the global pre-release alert. `inherit` keeps the global choice;
/// `off` cancels pre-release alerts for this title without unmuting it from the To Watch page.
enum AlertOverride: String, Codable, CaseIterable, Identifiable {
    case inherit, off, oneHour, oneDay, twoDays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit: return "Use global setting"
        case .off: return "Off"
        case .oneHour: return "1 hour before"
        case .oneDay: return "24 hours before"
        case .twoDays: return "48 hours before"
        }
    }

    func hours(global: Int?) -> Int? {
        switch self {
        case .inherit: return global
        case .off: return nil
        case .oneHour: return 1
        case .oneDay: return 24
        case .twoDays: return 48
        }
    }
}

struct WatchlistEntry: Codable, Identifiable, Hashable {
    var id: String { "\(mediaType.rawValue)-\(tmdbID)" }
    let tmdbID: Int
    let mediaType: MediaType
    var addedAt: Date
    var isTrackingEnabled: Bool
    /// Opt-in alert mute. The title stays tracked (isTrackingEnabled keeps feeding the
    /// To Watch page); muting only stops its alerts being scheduled.
    var alertsMuted: Bool? = nil
    /// Display-only ordering: pinned rows sort to the top of their list.
    var pinnedAt: Date? = nil
    /// Nil means "use the global pre-release setting", keeping old libraries compatible.
    var preAlertOverride: AlertOverride? = nil
}

/// One notice shown on To Watch after a refresh discovers a moved or newly announced release.
struct ScheduleChangeRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case dateChanged, newRelease
    }

    var id: String
    let titleID: String
    let key: String
    let titleName: String
    let label: String
    let kind: Kind
    let oldDate: Date?
    let newDate: Date?
    let detectedAt: Date
    var isRead: Bool = false
    /// Optional poster so a change banner can carry the show art. Old records decode nil.
    var posterPath: String? = nil
}

struct NotificationPreferences: Codable {
    var preAlertHours: Int? = 24
    var imminentAlertMinutes: Int? = 15
    var permissionRequested: Bool = false
    /// A 9 AM local summary of the next 24 hours. It supplements pre-release alerts:
    /// a daily recap must never swallow a warning that falls outside its window.
    var digestEnabled: Bool = false
    /// Fixed morning hour for the digest. Kept out of the UI until there is demand for a picker.
    var digestHour: Int = 9
    /// One batched banner when a refresh finds moved or newly announced releases.
    var notifyScheduleChanges: Bool = true

    init(
        preAlertHours: Int? = 24,
        imminentAlertMinutes: Int? = 15,
        permissionRequested: Bool = false,
        digestEnabled: Bool = false,
        digestHour: Int = 9,
        notifyScheduleChanges: Bool = true
    ) {
        self.preAlertHours = preAlertHours
        self.imminentAlertMinutes = imminentAlertMinutes
        self.permissionRequested = permissionRequested
        self.digestEnabled = digestEnabled
        self.digestHour = digestHour
        self.notifyScheduleChanges = notifyScheduleChanges
    }

    enum CodingKeys: String, CodingKey {
        case preAlertHours, imminentAlertMinutes, permissionRequested
        case digestEnabled, digestHour, notifyScheduleChanges
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `contains` keeps an explicit Off (`nil`) distinct from a key added in a later version.
        preAlertHours = c.contains(.preAlertHours)
            ? try c.decodeIfPresent(Int.self, forKey: .preAlertHours)
            : 24
        imminentAlertMinutes = c.contains(.imminentAlertMinutes)
            ? try c.decodeIfPresent(Int.self, forKey: .imminentAlertMinutes)
            : 15
        permissionRequested = try c.decodeIfPresent(Bool.self, forKey: .permissionRequested) ?? false
        digestEnabled = try c.decodeIfPresent(Bool.self, forKey: .digestEnabled) ?? false
        digestHour = try c.decodeIfPresent(Int.self, forKey: .digestHour) ?? 9
        notifyScheduleChanges = try c.decodeIfPresent(Bool.self, forKey: .notifyScheduleChanges) ?? true
    }
}

/// One item the user marked watched, with the timestamp needed for a diary. Legacy watched
/// sets migrate into records with `watchedAt == nil` rather than inventing a date.
struct WatchRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case episode, movie
    }

    let kind: Kind
    let titleID: String
    let itemID: String
    var watchedAt: Date?

    var id: String { "\(kind.rawValue):\(itemID)" }
}

/// A compact daily count that survives after the detailed diary records age out. One row per
/// local calendar day keeps lifetime, monthly, and streak stats intact without retaining every
/// watch forever.
struct WatchDaySummary: Codable, Identifiable, Equatable {
    var day: Date
    var episodes: Int
    var movies: Int

    var id: Date { day }
}

struct Library: Codable {
    static let currentSchemaVersion = 4

    var schemaVersion = Library.currentSchemaVersion
    var titles: [String: Title] = [:]
    var entries: [WatchlistEntry] = []
    var watchedShows: Set<String> = []
    var watchedMovies: Set<String> = []
    /// Episode IDs (`"100-s2e5"`) the user has marked watched.
    var watchedEpisodes: Set<String> = []
    var episodes: [String: [Episode]] = [:]
    var movieReleases: [String: [MovieRelease]] = [:]
    var preferences = NotificationPreferences()
    /// Newest first, capped by `ScheduleChangeRecorder`; old libraries decode to empty.
    var scheduleChanges: [ScheduleChangeRecord] = []
    /// Watched items with timestamps, used by the diary. The watched sets above stay
    /// authoritative for filtering and notification suppression. Only the most recent detail
    /// is retained; older days live on in `watchDays`.
    var watchLog: [WatchRecord] = []
    /// Lifetime daily aggregates. Pruning `watchLog` never changes these.
    var watchDays: [WatchDaySummary] = []
    /// Legacy watches that never had a timestamp. They are retained in `watchLog` and counted
    /// here because they cannot be assigned to a day.
    var undatedWatchCount = 0

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion, titles, entries, watchedShows, watchedMovies
        case watchedEpisodes, episodes, movieReleases, preferences, scheduleChanges, watchLog
        case watchDays, undatedWatchCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        titles = try c.decodeIfPresent([String: Title].self, forKey: .titles) ?? [:]
        entries = try c.decodeIfPresent([WatchlistEntry].self, forKey: .entries) ?? []
        watchedShows = try c.decodeIfPresent(Set<String>.self, forKey: .watchedShows) ?? []
        watchedMovies = try c.decodeIfPresent(Set<String>.self, forKey: .watchedMovies) ?? []
        watchedEpisodes = try c.decodeIfPresent(Set<String>.self, forKey: .watchedEpisodes) ?? []
        episodes = try c.decodeIfPresent([String: [Episode]].self, forKey: .episodes) ?? [:]
        movieReleases = try c.decodeIfPresent([String: [MovieRelease]].self, forKey: .movieReleases) ?? [:]
        preferences = try c.decodeIfPresent(NotificationPreferences.self, forKey: .preferences) ?? NotificationPreferences()
        scheduleChanges = try c.decodeIfPresent([ScheduleChangeRecord].self, forKey: .scheduleChanges) ?? []
        watchLog = try c.decodeIfPresent([WatchRecord].self, forKey: .watchLog) ?? []
        watchDays = try c.decodeIfPresent([WatchDaySummary].self, forKey: .watchDays) ?? []
        undatedWatchCount = try c.decodeIfPresent(Int.self, forKey: .undatedWatchCount) ?? 0
    }

    /// Marks a decoded legacy library as current, backfilling a diary record for every watched
    /// item that predates timestamps. The caller persists the result once, so a failed decode
    /// never silently rewrites the user's file.
    mutating func migrateSchemaIfNeeded(calendar: Calendar = .current) -> Bool {
        guard schemaVersion < Library.currentSchemaVersion else { return false }
        if schemaVersion < 3 {
            backfillWatchLog()
        }
        if schemaVersion < 4 {
            // Build the compact history before any pruning can discard the source records.
            rebuildWatchSummary(calendar: calendar)
        }
        schemaVersion = Library.currentSchemaVersion
        return true
    }

    private mutating func backfillWatchLog() {
        let known = Set(watchLog.map(\.id))
        for itemID in watchedEpisodes {
            let record = WatchRecord(
                kind: .episode,
                titleID: episodeTitleID(for: itemID),
                itemID: itemID,
                watchedAt: nil
            )
            if known.contains(record.id) == false, !record.titleID.isEmpty {
                watchLog.append(record)
            }
        }
        for titleID in watchedMovies {
            let record = WatchRecord(
                kind: .movie, titleID: titleID, itemID: titleID, watchedAt: nil
            )
            if known.contains(record.id) == false {
                watchLog.append(record)
            }
        }
    }

    /// Episode IDs carry the TMDB id (`"100-s2e5"`). Prefer the loaded episode's owning title;
    /// fall back to the id prefix when old data no longer has the episode.
    func episodeTitleID(for itemID: String) -> String {
        for (titleID, episodes) in episodes where episodes.contains(where: { $0.id == itemID }) {
            return titleID
        }
        guard let tmdbID = itemID.split(separator: "-").first else { return "" }
        return "tv-\(tmdbID)"
    }
}
