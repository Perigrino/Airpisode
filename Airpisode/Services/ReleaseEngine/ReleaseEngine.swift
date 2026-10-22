import Foundation

enum ReleaseChange: Equatable {
    case newRelease(titleID: String, key: String, date: Date?, hasTime: Bool)
    case dateChanged(titleID: String, key: String, old: Date?, new: Date?, hasTime: Bool)
    case releasePassed(titleID: String, key: String)
}

/// Refreshes stale tracked titles from TMDB and reports release-date changes.
/// Staleness tiers: release within 14d → 6h TTL; within 60d → 24h; else 7d.
struct ReleaseEngine {
    let client: TMDBClientProtocol
    /// Region release dates are fetched for. Defaults to the user's stored setting at
    /// construction; tests pass an explicit region so they never depend on machine config.
    var region: String = ConfigStore.defaultRegion
    /// Optional exact-air-time lookup (TVmaze). A failure simply leaves episodes date-only.
    var airTimes: AirTimeProviding? = nil

    func refreshIfNeeded(library: inout Library, now: Date, force: Bool = false) async -> [ReleaseChange] {
        var changes: [ReleaseChange] = []
        for entry in library.entries where entry.isTrackingEnabled {
            guard let title = library.titles[entry.id] else { continue }
            if !force, isFresh(title: title, library: library, now: now) { continue }
            let titleID = entry.id
            let previousRefreshed = title.lastRefreshed
            do {
                switch entry.mediaType {
                case .tv:
                    let detail = try await client.tvDetail(id: entry.tmdbID)
                    var newTitle = TMDBMapper.title(from: detail)
                    var episodes: [Episode] = []
                    for season in detail.seasons where shouldFetch(season: season, now: now) {
                        let seasonData = try await client.season(tvID: entry.tmdbID, season: season.seasonNumber)
                        episodes += TMDBMapper.episodes(seasonData, tvID: entry.tmdbID)
                    }
                    episodes = await AirTimeEnricher.enrich(
                        episodes,
                        previous: library.episodes[titleID] ?? [],
                        detail: detail,
                        provider: airTimes,
                        now: now
                    )
                    changes += Self.diff(
                        old: library.episodes[titleID] ?? [], new: episodes,
                        titleID: titleID, lastRefreshed: previousRefreshed, now: now,
                        id: { $0.id }, date: { $0.airDate }, hasTime: { _ in false }
                    )
                    newTitle.lastRefreshed = now
                    library.titles[titleID] = newTitle
                    library.episodes[titleID] = episodes
                case .movie:
                    let detail = try await client.movieDetail(id: entry.tmdbID)
                    var newTitle = TMDBMapper.title(from: detail)
                    let response = try await client.movieReleaseDates(id: entry.tmdbID)
                    let region = self.region
                    let releases = TMDBMapper.movieReleases(response, movieID: entry.tmdbID, region: region)
                    changes += Self.diff(
                        old: library.movieReleases[titleID] ?? [], new: releases,
                        titleID: titleID, lastRefreshed: previousRefreshed, now: now,
                        id: { $0.id }, date: { $0.date }, hasTime: { $0.hasTime }
                    )
                    newTitle.lastRefreshed = now
                    library.titles[titleID] = newTitle
                    library.movieReleases[titleID] = releases
                }
            } catch {
                continue  // keep last good data; lastRefreshed stays put so next pass retries
            }
        }
        return changes
    }

    // MARK: - Staleness

    private func isFresh(title: Title, library: Library, now: Date) -> Bool {
        guard let refreshed = title.lastRefreshed else { return false }
        let dates = (library.episodes[title.id] ?? []).compactMap(\.airDate)
            + (library.movieReleases[title.id] ?? []).compactMap(\.date)
        let next = dates.filter { $0 >= now }.min()
        let ttl: TimeInterval
        if let next {
            let days = next.timeIntervalSince(now) / 86_400
            ttl = days <= 14 ? 6 * 3600 : days <= 60 ? 24 * 3600 : 7 * 86_400
        } else {
            ttl = 7 * 86_400
        }
        return now.timeIntervalSince(refreshed) < ttl
    }

    /// Skip specials; skip seasons that ended more than a year ago; unknown airDate → fetch.
    private func shouldFetch(season: TMDBSeasonSummary, now: Date) -> Bool {
        guard season.seasonNumber > 0 else { return false }
        guard let airDate = season.airDate.flatMap(TMDBMapper.parseDate) else { return true }
        return airDate > now.addingTimeInterval(-365 * 86_400)
    }

    // MARK: - Diffing

    static func diff<Item>(
        old: [Item], new: [Item], titleID: String, lastRefreshed: Date?, now: Date,
        id: (Item) -> String, date: (Item) -> Date?, hasTime: (Item) -> Bool
    ) -> [ReleaseChange] {
        var changes: [ReleaseChange] = []
        // TMDB can report several dates of the same type in a region, so `old` may
        // contain duplicate ids. Build the lookup defensively rather than trapping.
        var oldByID: [String: Item] = [:]
        for item in old { oldByID[id(item)] = item }
        for item in new {
            let key = id(item)
            if let prev = oldByID[key] {
                let oldDate = date(prev), newDate = date(item)
                if oldDate != newDate {
                    changes.append(.dateChanged(titleID: titleID, key: key, old: oldDate, new: newDate, hasTime: hasTime(item)))
                } else if let d = oldDate, let refreshed = lastRefreshed, d >= refreshed, d < now {
                    // Unchanged date that has since passed — it was still upcoming at last look.
                    changes.append(.releasePassed(titleID: titleID, key: key))
                }
            } else {
                changes.append(.newRelease(titleID: titleID, key: key, date: date(item), hasTime: hasTime(item)))
            }
        }
        return changes
    }
}
