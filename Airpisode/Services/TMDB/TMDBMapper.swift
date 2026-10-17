import Foundation

/// Maps TMDB DTOs into domain models, preserving date certainty.
/// Date-only values ("YYYY-MM-DD") become noon-UTC Dates (avoids DST day-shifts).
/// Full ISO datetimes become exact Dates.
enum TMDBMapper {

    static func title(from detail: TMDBTVDetail) -> Title {
        Title(
            tmdbID: detail.id,
            mediaType: .tv,
            name: detail.name,
            overview: detail.overview ?? "",
            posterPath: detail.posterPath,
            firstAirDate: detail.firstAirDate.flatMap(parseDate),
            tvStatus: detail.status,
            seasons: detail.seasons.map { SeasonSummary(seasonNumber: $0.seasonNumber, episodeCount: $0.episodeCount, airDate: $0.airDate.flatMap(parseDate)) },
            lastRefreshed: nil
        )
    }

    static func title(from detail: TMDBMovieDetail) -> Title {
        Title(
            tmdbID: detail.id,
            mediaType: .movie,
            name: detail.title,
            overview: detail.overview ?? "",
            posterPath: detail.posterPath,
            firstAirDate: detail.releaseDate.flatMap(parseDate),
            tvStatus: nil,
            seasons: [],
            lastRefreshed: nil
        )
    }

    static func episodes(_ season: TMDBSeason, tvID: Int) -> [Episode] {
        season.episodes.map { ep in
            Episode(
                tmdbID: tvID,
                seasonNumber: ep.seasonNumber,
                episodeNumber: ep.episodeNumber,
                name: ep.name,
                overview: ep.overview,
                airDate: ep.airDate.flatMap(parseDate),
                stillPath: ep.stillPath
            )
        }
    }

    /// Maps a movie's release dates for `region`. TMDB can list several dates of the
    /// same type in one region (e.g. two TV windows), which would collide on `id`, so
    /// keep one per kind: the next upcoming date, else the most recent one.
    static func movieReleases(_ response: TMDBReleaseDatesResponse, movieID: Int, region: String, now: Date = .now) -> [MovieRelease] {
        guard let regionEntry = response.results.first(where: { $0.iso3166_1 == region }) else { return [] }
        var order: [String] = []
        var chosen: [String: MovieRelease] = [:]
        for entry in regionEntry.releaseDates {
            guard let kind = kind(from: entry.type) else { continue }
            let date: Date?
            let hasTime: Bool
            if let dt = parseDateTime(entry.releaseDate) {
                date = dt; hasTime = true
            } else if let d = parseDate(entry.releaseDate) {
                date = d; hasTime = false
            } else {
                continue
            }
            let release = MovieRelease(tmdbID: movieID, kind: kind, region: region, date: date, hasTime: hasTime)
            if let existing = chosen[release.id] {
                chosen[release.id] = pick(existing, release, now: now)
            } else {
                chosen[release.id] = release
                order.append(release.id)
            }
        }
        return order.compactMap { chosen[$0] }
    }

    /// Prefers the earliest date at or after `now`; otherwise the most recent date.
    private static func pick(_ a: MovieRelease, _ b: MovieRelease, now: Date) -> MovieRelease {
        func rank(_ r: MovieRelease) -> (bucket: Int, date: Date) {
            guard let d = r.date else { return (2, .distantPast) }
            return d >= now ? (0, d) : (1, d)
        }
        let ra = rank(a), rb = rank(b)
        if ra.bucket != rb.bucket { return ra.bucket < rb.bucket ? a : b }
        // Upcoming: earliest wins. Past/undated: latest wins.
        return ra.bucket == 1 ? (ra.date >= rb.date ? a : b) : (ra.date <= rb.date ? a : b)
    }

    private static func kind(from type: Int) -> ReleaseKind? {
        switch type {
        case 1: return .theatrical
        case 2: return .digital
        case 3: return .physical
        case 4: return .tv
        default: return nil
        }
    }

    // MARK: - Date parsing

    /// "YYYY-MM-DD" → noon UTC, hasTime false semantics live at call site.
    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: s) else { return nil }
        return Calendar(identifier: .gregorian).date(bySettingHour: 12, minute: 0, second: 0, of: d, matchingPolicy: .strict)
    }

    /// Full ISO datetime; prefers fractional seconds, falls back to plain ISO8601.
    static func parseDateTime(_ s: String) -> Date? {
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
