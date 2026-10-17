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
}

struct Episode: Codable, Identifiable, Hashable {
    var id: String { "\(tmdbID)-s\(seasonNumber)e\(episodeNumber)" }
    let tmdbID: Int
    let seasonNumber: Int
    let episodeNumber: Int
    var name: String
    var overview: String?
    var airDate: Date?
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

struct WatchlistEntry: Codable, Identifiable, Hashable {
    var id: String { "\(mediaType.rawValue)-\(tmdbID)" }
    let tmdbID: Int
    let mediaType: MediaType
    var addedAt: Date
    var isTrackingEnabled: Bool
}

struct NotificationPreferences: Codable {
    var preAlertHours: Int? = 24
    var imminentAlertMinutes: Int? = 15
    var permissionRequested: Bool = false
}

struct Library: Codable {
    var schemaVersion = 1
    var titles: [String: Title] = [:]
    var entries: [WatchlistEntry] = []
    var watchedShows: Set<String> = []
    var watchedMovies: Set<String> = []
    /// Episode IDs (`"100-s2e5"`) the user has marked watched.
    var watchedEpisodes: Set<String> = []
    var episodes: [String: [Episode]] = [:]
    var movieReleases: [String: [MovieRelease]] = [:]
    var preferences = NotificationPreferences()
}
