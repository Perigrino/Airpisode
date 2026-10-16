import XCTest
@testable import Airpisode

final class ReleaseEngineTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!  // noon UTC

    private func tvDetail() -> TMDBTVDetail {
        TMDBTVDetail(id: 100, name: "Severance", overview: nil, posterPath: nil, firstAirDate: nil,
                     status: "Returning Series",
                     seasons: [TMDBSeasonSummary(seasonNumber: 1, episodeCount: 1, airDate: "2026-09-01")])
    }

    private func makeLibrary(lastRefreshed: Date?, oldAirDate: String?) -> Library {
        var lib = Library()
        var title = TMDBMapper.title(from: tvDetail())
        title.lastRefreshed = lastRefreshed
        lib.titles["tv-100"] = title
        lib.entries = [WatchlistEntry(tmdbID: 100, mediaType: .tv, addedAt: now, isTrackingEnabled: true)]
        if let oldAirDate {
            lib.episodes["tv-100"] = [
                Episode(tmdbID: 100, seasonNumber: 1, episodeNumber: 1, name: "Ep", overview: nil,
                        airDate: TMDBMapper.parseDate(oldAirDate), stillPath: nil)
            ]
        }
        return lib
    }

    private func stubWithSeason(airDate: String) -> StubTMDBClient {
        let stub = StubTMDBClient()
        stub.tvDetailResult = tvDetail()
        stub.seasons[1] = TMDBSeason(seasonNumber: 1, episodes: [
            TMDBTVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep", overview: nil, airDate: airDate, stillPath: nil)
        ])
        return stub
    }

    func testFreshTitleNotRefetched() async {
        // last refreshed 1h ago; next release in 4 days → within-14d tier → 6h TTL → fresh.
        var lib = makeLibrary(lastRefreshed: now.addingTimeInterval(-3600), oldAirDate: "2026-10-20")
        let stub = stubWithSeason(airDate: "2026-10-20")
        let changes = await ReleaseEngine(client: stub).refreshIfNeeded(library: &lib, now: now)
        XCTAssertEqual(stub.tvDetailCallCount, 0)
        XCTAssertTrue(changes.isEmpty)
    }

    func testStaleTitleRefetchedAndLastRefreshedUpdated() async {
        // 7h ago exceeds the 6h TTL for a near-term release.
        var lib = makeLibrary(lastRefreshed: now.addingTimeInterval(-7 * 3600), oldAirDate: "2026-10-20")
        let stub = stubWithSeason(airDate: "2026-10-20")
        _ = await ReleaseEngine(client: stub).refreshIfNeeded(library: &lib, now: now)
        XCTAssertEqual(stub.tvDetailCallCount, 1)
        XCTAssertEqual(stub.seasonCallNumbers, [1])
        XCTAssertEqual(lib.titles["tv-100"]?.lastRefreshed, now)
    }

    func testSameAirDateProducesNoChanges() async {
        var lib = makeLibrary(lastRefreshed: now.addingTimeInterval(-7 * 3600), oldAirDate: "2026-10-20")
        let stub = stubWithSeason(airDate: "2026-10-20")
        let changes = await ReleaseEngine(client: stub).refreshIfNeeded(library: &lib, now: now)
        XCTAssertTrue(changes.isEmpty)
    }

    func testShiftedAirDateProducesOneDateChanged() async {
        var lib = makeLibrary(lastRefreshed: now.addingTimeInterval(-7 * 3600), oldAirDate: "2026-10-20")
        let stub = stubWithSeason(airDate: "2026-10-27")
        let changes = await ReleaseEngine(client: stub).refreshIfNeeded(library: &lib, now: now)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(
            changes.first,
            .dateChanged(titleID: "tv-100", key: "100-s1e1",
                         old: TMDBMapper.parseDate("2026-10-20"),
                         new: TMDBMapper.parseDate("2026-10-27"),
                         hasTime: false)
        )
    }

    func testNewEpisodeProducesNewRelease() async {
        // No stored episodes → 7d TTL; refreshed 8d ago → stale.
        var lib = makeLibrary(lastRefreshed: now.addingTimeInterval(-8 * 86_400), oldAirDate: nil)
        lib.episodes["tv-100"] = []
        let stub = stubWithSeason(airDate: "2026-10-20")
        let changes = await ReleaseEngine(client: stub).refreshIfNeeded(library: &lib, now: now)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(
            changes.first,
            .newRelease(titleID: "tv-100", key: "100-s1e1", date: TMDBMapper.parseDate("2026-10-20"), hasTime: false)
        )
    }

    func testReleasePassedWhenDateFellBetweenRefreshes() async {
        // Past episode → 7d TTL; last look 8d ago was before the episode aired (2026-10-15).
        var lib = makeLibrary(lastRefreshed: now.addingTimeInterval(-8 * 86_400), oldAirDate: "2026-10-15")
        // Engine skips seasons >1yr past; season airDate is recent, so the past episode still comes back.
        let stub = stubWithSeason(airDate: "2026-10-15")
        let changes = await ReleaseEngine(client: stub).refreshIfNeeded(library: &lib, now: now)
        // Same past date: no dateChanged; releasePassed fires because it passed since last look.
        XCTAssertEqual(changes, [.releasePassed(titleID: "tv-100", key: "100-s1e1")])
    }

    func testSkipsSpecialsAndOldSeasons() async {
        var lib = makeLibrary(lastRefreshed: now.addingTimeInterval(-7 * 3600), oldAirDate: "2026-10-20")
        let stub = StubTMDBClient()
        stub.tvDetailResult = TMDBTVDetail(id: 100, name: "Severance", overview: nil, posterPath: nil, firstAirDate: nil,
                                           status: nil, seasons: [
            TMDBSeasonSummary(seasonNumber: 0, episodeCount: 5, airDate: "2026-01-01"),   // specials → skip
            TMDBSeasonSummary(seasonNumber: 1, episodeCount: 1, airDate: "2020-01-01"),   // >1yr past → skip
            TMDBSeasonSummary(seasonNumber: 2, episodeCount: 1, airDate: "2026-09-01"),   // recent → fetch
        ])
        stub.seasons[2] = TMDBSeason(seasonNumber: 2, episodes: [
            TMDBTVEpisode(episodeNumber: 1, seasonNumber: 2, name: "Ep2", overview: nil, airDate: "2026-10-20", stillPath: nil)
        ])
        _ = await ReleaseEngine(client: stub).refreshIfNeeded(library: &lib, now: now)
        XCTAssertEqual(stub.seasonCallNumbers, [2])
    }
}
