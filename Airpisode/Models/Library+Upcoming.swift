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
                guard let airDate = episode.airDate, airDate >= now else { return false }
                return !watchedShows.contains(episode.id)
            }
            .min { ($0.airDate ?? .distantFuture) < ($1.airDate ?? .distantFuture) }
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
                        date: episode.airDate,
                        label: "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name)",
                        isTimed: false  // TMDB episode air dates are date-only
                    ))
                }
            case .movie:
                if let release = (movieReleases[entry.id] ?? [])
                    .filter({ ($0.date ?? .distantPast) >= now })
                    .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }) {
                    items.append(UpcomingItem(
                        title: title,
                        date: release.date,
                        label: release.kind.label,
                        isTimed: release.hasTime
                    ))
                }
            }
        }
        return items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}
