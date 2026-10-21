import Foundation

/// TVmaze publishes exact air instants (`airstamp`) that TMDB does not. Shows are looked
/// up by TVDB/IMDb ID from TMDB's `external_ids`, so a same-named show cannot be mistaken
/// for another. TVmaze allows 20 requests per 10 seconds; requests are spaced accordingly.
actor TVmazeClient: AirTimeProviding {
    private struct ShowDTO: Decodable {
        let id: Int
    }

    private struct AiringDTO: Decodable {
        let season: Int
        let number: Int?
        let airstamp: String?
    }

    private let session: URLSession
    private let minimumInterval: TimeInterval
    private static let cacheLifetime: TimeInterval = 3600
    private var lastRequestAt: Date?
    private var showIDs: [AirTimeRequest: Int] = [:]
    private var schedules: [Int: (fetchedAt: Date, timestamps: [EpisodeKey: Date])] = [:]

    init(
        session: URLSession = .shared,
        minimumInterval: TimeInterval = 0.55
    ) {
        self.session = session
        self.minimumInterval = minimumInterval
    }

    func airTimestamps(for show: AirTimeRequest, episodes: [Episode]) async -> [EpisodeKey: Date] {
        guard let showID = await resolveShowID(for: show) else { return [:] }
        if let cached = schedules[showID],
           Date().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return cached.timestamps
        }
        guard let data = try? await get(path: "/shows/\(showID)/episodes"),
              let decoded = try? JSONDecoder().decode([AiringDTO].self, from: data) else {
            return [:]
        }
        var timestamps: [EpisodeKey: Date] = [:]
        for airing in decoded {
            guard let number = airing.number,
                  let airstamp = airing.airstamp,
                  let date = TMDBMapper.parseDateTime(airstamp) else { continue }
            timestamps[EpisodeKey(season: airing.season, number: number)] = date
        }
        schedules[showID] = (Date(), timestamps)
        return timestamps
    }

    private func resolveShowID(for show: AirTimeRequest) async -> Int? {
        if let cached = showIDs[show] { return cached }
        var lookups: [URLQueryItem] = []
        if let tvdbID = show.tvdbID {
            lookups.append(URLQueryItem(name: "thetvdb", value: String(tvdbID)))
        }
        if let imdbID = show.imdbID {
            lookups.append(URLQueryItem(name: "imdb", value: imdbID))
        }
        for lookup in lookups {
            guard let data = try? await get(path: "/lookup/shows", query: [lookup]),
                  let decoded = try? JSONDecoder().decode(ShowDTO.self, from: data) else { continue }
            showIDs[show] = decoded.id
            return decoded.id
        }
        return nil
    }

    private func get(path: String, query: [URLQueryItem] = [], attempt: Int = 0) async throws -> Data {
        try await waitForTurn()
        var components = URLComponents(string: "https://api.tvmaze.com")!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429, attempt < 2 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 1
            lastRequestAt = nil
            try await Task.sleep(nanoseconds: UInt64(max(retryAfter, 0.5) * 1_000_000_000))
            return try await get(path: path, query: query, attempt: attempt + 1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// TVmaze permits 20 requests per 10 seconds per IP; spacing requests keeps a full
    /// library refresh comfortably under that.
    private func waitForTurn() async throws {
        if let lastRequestAt {
            let elapsed = Date().timeIntervalSince(lastRequestAt)
            if elapsed < minimumInterval {
                let remaining = minimumInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastRequestAt = Date()
    }
}
