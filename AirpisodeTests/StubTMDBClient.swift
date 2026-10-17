import Foundation
@testable import Airpisode

/// In-memory TMDB client for tests. Assign canned results per test; call counts are recorded.
final class StubTMDBClient: TMDBClientProtocol, @unchecked Sendable {
    var searchResults: [TMDBSearchResult] = []
    var lastQuery: String?
    var tvDetailResult: TMDBTVDetail?
    var seasons: [Int: TMDBSeason] = [:]
    var movieDetailResult: TMDBMovieDetail?
    var releaseDatesResult: TMDBReleaseDatesResponse?
    var tvDetailCallCount = 0
    var movieDetailCallCount = 0
    var seasonCallNumbers: [Int] = []
    var similarTitles: [String: [TMDBSearchResult]] = [:]  // key "tv-123"
    var similarRequests: [String] = []
    var recommendationTitles: [String: [TMDBSearchResult]] = [:]
    var recommendationRequests: [String] = []
    var creditsResult: [TMDBCastMember] = []

    /// `recommendations`/`similar` are called concurrently by RecommendationEngine's task group,
    /// so recorded requests need a lock or appends get lost.
    private let lock = NSLock()

    func searchMulti(query: String) async throws -> [TMDBSearchResult] {
        lastQuery = query
        return searchResults
    }

    func tvDetail(id: Int) async throws -> TMDBTVDetail {
        tvDetailCallCount += 1
        guard let tvDetailResult else { throw URLError(.badServerResponse) }
        return tvDetailResult
    }

    func season(tvID: Int, season: Int) async throws -> TMDBSeason {
        seasonCallNumbers.append(season)
        guard let s = seasons[season] else { throw URLError(.badServerResponse) }
        return s
    }

    func movieDetail(id: Int) async throws -> TMDBMovieDetail {
        movieDetailCallCount += 1
        guard let movieDetailResult else { throw URLError(.badServerResponse) }
        return movieDetailResult
    }

    func movieReleaseDates(id: Int) async throws -> TMDBReleaseDatesResponse {
        guard let releaseDatesResult else { throw URLError(.badServerResponse) }
        return releaseDatesResult
    }

    func similar(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBSearchResult] {
        let key = "\(mediaType.rawValue)-\(tmdbID)"
        lock.lock()
        similarRequests.append(key)
        lock.unlock()
        return similarTitles[key] ?? []
    }

    func credits(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBCastMember] {
        creditsResult
    }

    func recommendations(mediaType: MediaType, tmdbID: Int) async throws -> [TMDBSearchResult] {
        let key = "\(mediaType.rawValue)-\(tmdbID)"
        lock.lock()
        recommendationRequests.append(key)
        lock.unlock()
        return recommendationTitles[key] ?? []
    }
}
