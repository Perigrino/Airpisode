import Foundation

protocol TMDBClientProtocol: Sendable {
    func searchMulti(query: String) async throws -> [TMDBSearchResult]
    func tvDetail(id: Int) async throws -> TMDBTVDetail
    func season(tvID: Int, season: Int) async throws -> TMDBSeason
    func movieDetail(id: Int) async throws -> TMDBMovieDetail
    func movieReleaseDates(id: Int) async throws -> TMDBReleaseDatesResponse
}

struct TMDBClient: TMDBClientProtocol {
    let apiKey: String
    var session: URLSession = .shared
    private static let base = URL(string: "https://api.themoviedb.org/3")!
    private static let decoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var comps = URLComponents(url: TMDBClient.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query + [URLQueryItem(name: "api_key", value: apiKey)]
        let (data, response) = try await session.data(from: comps.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
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
}
