import Foundation

struct UpcomingItem: Identifiable {
    let title: Title
    let date: Date?
    let label: String
    let isTimed: Bool
    var id: String { title.id }
}

extension Library {
    /// Earliest unwatched episode with a known air date at or after `now`.
    func nextEpisode(forTitle titleID: String, now: Date = .now) -> Episode? {
        (episodes[titleID] ?? [])
            .filter { episode in
                guard let airDate = airMoment(episode), airDate >= now else { return false }
                return !watchedEpisodes.contains(episode.id)
            }
            .min { (airMoment($0) ?? .distantFuture) < (airMoment($1) ?? .distantFuture) }
    }

    /// All tracked titles' next release, sorted soonest-first. Date-only items keep `isTimed == false`.
    func upcomingReleases(now: Date = .now) -> [UpcomingItem] {
        var items: [UpcomingItem] = []
        for entry in entries where entry.isTrackingEnabled {
            guard let title = titles[entry.id] else { continue }
            switch entry.mediaType {
            case .tv:
                if let episode = nextEpisode(forTitle: entry.id, now: now) {
                    items.append(UpcomingItem(
                        title: title,
                        date: airMoment(episode),
                        label: "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name)",
                        isTimed: episode.airTimestamp != nil
                    ))
                } else if let airing = title.nextAiring, let date = airing.airDate, date >= now {
                    // No fetched upcoming episode (e.g. the next season hasn't started), but
                    // TMDB already knows when the next one airs.
                    items.append(UpcomingItem(
                        title: title,
                        date: date,
                        label: "S\(airing.seasonNumber)E\(airing.episodeNumber) · \(airing.name)",
                        isTimed: false
                    ))
                }
            case .movie:
                if let release = (movieReleases[entry.id] ?? [])
                    .filter({ ($0.date ?? .distantPast) >= now })
                    .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }) {
                    // Format + region, matching the Released-and-waiting card, so a movie that
                    // appears both places (e.g. past physical + future digital) is never ambiguous.
                    items.append(UpcomingItem(
                        title: title,
                        date: release.date,
                        label: "\(release.kind.label) · \(release.region)",
                        isTimed: release.hasTime
                    ))
                }
            }
        }
        return items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// An exact air instant when one is known, otherwise TMDB's date-only value.
    private func airMoment(_ episode: Episode) -> Date? {
        episode.airTimestamp ?? episode.airDate
    }
}
