import Foundation

/// Errors worth naming. TMDB answers 401 for a missing or wrong key, and a bare
/// `URLError(.badServerResponse)` would surface that to the user as "-1011".
enum TMDBError: LocalizedError, Equatable {
    case missingKey
    case notFound
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Your TMDB API key is missing or invalid. Add it in Settings."
        case .notFound:
            "TMDB has no record of that title."
        case .server(let code):
            "TMDB returned an error (HTTP \(code)). Try again in a moment."
        }
    }
}

protocol TMDBClientProtocol: Sendable {
    func searchMulti(query: String) async throws -> [TMDBSearchResult]
    func tvDetail(id: Int) async throws -> TMDBTVDetail
    func season(tvID: Int, season: Int) async throws -> TMDBSeason
    func movieDetail(id: Int) async throws -> TMDBMovieDetail
    func movieReleaseDates(id: Int) async throws -> TMDBReleaseDatesResponse
    func videos(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBVideo]
    func watchProviders(mediaType: MediaType, tmdbID: Int) async throws -> TMDBWatchProvidersResponse
    func similar(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBSearchResult]
    func recommendations(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBSearchResult]
    func credits(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBCastMember]
    func person(tmdbID: Int) async throws -> TMDBPersonDetail
}

struct TMDBClient: TMDBClientProtocol {
    /// Resolved per request, so a key entered in Settings takes effect without rebuilding clients.
    let apiKey: @Sendable () -> String
    var session: URLSession = .shared
    private static let base = URL(string: "https://api.themoviedb.org/3")!
    private static let decoder = JSONDecoder()

    init(apiKey: @escaping @Sendable () -> String = { Secrets.tmdbKey }, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var comps = URLComponents(url: TMDBClient.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query + [URLQueryItem(name: "api_key", value: apiKey())]
        let (data, response) = try await session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw TMDBError.missingKey
        case 404:
            throw TMDBError.notFound
        default:
            throw TMDBError.server(http.statusCode)
        }
        return try TMDBClient.decoder.decode(T.self, from: data)
    }
    func searchMulti(query: String) async throws -> [TMDBSearchResult] {
        let page: TMDBSearchResponse = try await get("search/multi", query: [URLQueryItem(name: "query", value: query)])
        return page.results
    }
    func tvDetail(id: Int) async throws -> TMDBTVDetail {
        try await get("tv/\(id)")
    }
    func season(tvID: Int, season: Int) async throws -> TMDBSeason {
        try await get("tv/\(tvID)/season/\(season)")
    }
    func movieDetail(id: Int) async throws -> TMDBMovieDetail {
        try await get("movie/\(id)")
    }
    func movieReleaseDates(id: Int) async throws -> TMDBReleaseDatesResponse {
        try await get("movie/\(id)/release_dates")
    }
    func videos(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBVideo] {
        let page: TMDBVideosResponse = try await get("\(mediaType.rawValue)/\(tmdbID)/videos")
        return page.results
    }
    func watchProviders(mediaType: MediaType, tmdbID: Int) async throws -> TMDBWatchProvidersResponse {
        try await get("\(mediaType.rawValue)/\(tmdbID)/watch/providers")
    }
    /// `/similar` and `/recommendations` share a response shape, and both omit media_type.
    private func mapped(_ page: TMDBRecommendationsResponse, mediaType: MediaType) -> [TMDBSearchResult] {
        page.results.map {
            TMDBSearchResult(
                id: $0.id, mediaType: mediaType.rawValue, name: $0.name, title: $0.title,
                overview: $0.overview, posterPath: $0.posterPath,
                firstAirDate: $0.firstAirDate, releaseDate: $0.releaseDate,
                popularity: $0.popularity, voteAverage: $0.voteAverage, voteCount: $0.voteCount
            )
        }
    }
    func similar(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBSearchResult] {
        let page: TMDBRecommendationsResponse = try await get("\(mediaType.rawValue)/\(tmdbID)/similar")
        return mapped(page, mediaType: mediaType)
    }
    func recommendations(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBSearchResult] {
        let page: TMDBRecommendationsResponse = try await get("\(mediaType.rawValue)/\(tmdbID)/recommendations")
        return mapped(page, mediaType: mediaType)
    }
    func credits(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBCastMember] {
        let page: TMDBCreditsResponse = try await get("\(mediaType.rawValue)/\(tmdbID)/credits")
        return page.cast
    }
    func person(tmdbID: Int) async throws -> TMDBPersonDetail {
        try await get("person/\(tmdbID)")
    }
}
