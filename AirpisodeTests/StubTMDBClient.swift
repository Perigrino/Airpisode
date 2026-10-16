import Foundation
@testable import Airpisode

/// In-memory TMDB client for tests. Assign results per test; each method records its last input.
final class StubTMDBClient: TMDBClientProtocol, @unchecked Sendable {
    var searchResults: [TMDBSearchResult] = []
    var lastQuery: String?

    func searchMulti(query: String) async throws -> [TMDBSearchResult] {
        lastQuery = query
        return searchResults
    }

    func tvDetail(id: Int) async throws -> TMDBTVDetail { fatalError("not stubbed") }
    func season(tvID: Int, season: Int) async throws -> TMDBSeason { fatalError("not stubbed") }
    func movieDetail(id: Int) async throws -> TMDBMovieDetail { fatalError("not stubbed") }
    func movieReleaseDates(id: Int) async throws -> TMDBReleaseDatesResponse { fatalError("not stubbed") }
}
