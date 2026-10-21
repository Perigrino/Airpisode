import Foundation

/// Identifies one episode within a show, independent of the data source.
struct EpisodeKey: Hashable, Sendable {
    let season: Int
    let number: Int

    init(season: Int, number: Int) {
        self.season = season
        self.number = number
    }

    init(_ episode: Episode) {
        self.init(season: episode.seasonNumber, number: episode.episodeNumber)
    }
}

/// The identifiers a provider needs to find a show in its own catalog.
struct AirTimeRequest: Hashable, Sendable {
    let tvdbID: Int?
    let imdbID: String?
}

protocol AirTimeProviding: Sendable {
    /// Exact air instants keyed by season/episode. Returns an empty map when the show
    /// or its schedule is unavailable: a missed lookup must never block a TMDB refresh.
    func airTimestamps(for show: AirTimeRequest, episodes: [Episode]) async -> [EpisodeKey: Date]
}

enum AirTimeEnricher {
    /// TMDB stores date-only air dates at noon UTC. A US evening broadcast lands up to
    /// about 12 hours later, so look slightly into the past as well as ahead.
    static let lookBack: TimeInterval = 24 * 3600
    static let lookAhead: TimeInterval = 7 * 24 * 3600

    /// Carries known timestamps forward, then asks the provider for exact times for the
    /// near-term episodes that can still produce an alert.
    static func enrich(
        _ episodes: [Episode],
        previous: [Episode] = [],
        detail: TMDBTVDetail,
        provider: AirTimeProviding?,
        now: Date
    ) async -> [Episode] {
        var result = episodes
        // Carry a known timestamp only while the TMDB date is unchanged; a delayed
        // episode must not keep its old air time.
        var carried: [String: (airDate: Date?, timestamp: Date)] = [:]
        for episode in previous {
            if let timestamp = episode.airTimestamp {
                carried[episode.id] = (episode.airDate, timestamp)
            }
        }
        for index in result.indices {
            if let known = carried[result[index].id], known.airDate == result[index].airDate {
                result[index].airTimestamp = known.timestamp
            }
        }
        guard let provider else { return result }

        let window = result.filter { episode in
            guard let airDate = episode.airDate else { return false }
            return airDate > now.addingTimeInterval(-lookBack)
                && airDate < now.addingTimeInterval(lookAhead)
        }
        guard !window.isEmpty else { return result }

        let request = AirTimeRequest(
            tvdbID: detail.externalIDs?.tvdbID,
            imdbID: detail.externalIDs?.imdbID
        )
        let timestamps = await provider.airTimestamps(for: request, episodes: window)
        for index in result.indices {
            if let timestamp = timestamps[EpisodeKey(result[index])] {
                result[index].airTimestamp = timestamp
            }
        }
        return result
    }
}
