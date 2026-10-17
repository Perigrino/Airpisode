import XCTest
@testable import Airpisode

@MainActor
final class AppStateLibraryTests: XCTestCase {
    private func makeSUT() -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return AppState(store: LibraryStore(directory: dir), tmdb: StubTMDBClient())
    }

    private func sampleTitle(tmdbID: Int = 100, mediaType: MediaType = .tv) -> Title {
        Title(tmdbID: tmdbID, mediaType: mediaType, name: "Severance", overview: "", posterPath: nil, firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
    }

    func testAddToLibraryIsIdempotent() {
        let app = makeSUT()
        let title = sampleTitle()
        app.addToLibrary(title)
        app.addToLibrary(title)
        XCTAssertEqual(app.library.entries.count, 1)
        XCTAssertEqual(app.library.titles.count, 1)
    }

    func testRemoveDeletesTitleAndEpisodes() {
        let app = makeSUT()
        let title = sampleTitle()
        app.addToLibrary(title)
        app.library.episodes["tv-100"] = [
            Episode(tmdbID: 100, seasonNumber: 1, episodeNumber: 1, name: "Good News", overview: nil, airDate: nil, stillPath: nil)
        ]
        app.removeFromLibrary("tv-100")
        XCTAssertTrue(app.library.entries.isEmpty)
        XCTAssertNil(app.library.titles["tv-100"])
        XCTAssertNil(app.library.episodes["tv-100"])
    }

    func testLoadLibraryPersistsAcrossInstances() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = AppState(store: LibraryStore(directory: dir), tmdb: StubTMDBClient())
        first.addToLibrary(sampleTitle())
        // Wait for the fire-and-forget save task to land.
        try await Task.sleep(nanoseconds: 200_000_000)

        let second = AppState(store: LibraryStore(directory: dir), tmdb: StubTMDBClient())
        await second.loadLibrary()
        XCTAssertEqual(second.library.entries.count, 1)
        XCTAssertEqual(second.library.entries.first?.id, "tv-100")
    }

    func testRefreshTitleFetchesTVEpisodesAndSetsLastRefreshed() async {
        let stub = StubTMDBClient()
        stub.tvDetailResult = TMDBTVDetail(
            id: 100, name: "Severance", overview: nil, posterPath: nil, firstAirDate: nil,
            status: "Returning Series",
            seasons: [TMDBSeasonSummary(seasonNumber: 1, episodeCount: 2, airDate: nil)]
        )
        stub.seasons[1] = TMDBSeason(seasonNumber: 1, episodes: [
            TMDBTVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Good News", overview: nil, airDate: "2022-02-18", stillPath: nil),
            TMDBTVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Half Loop", overview: nil, airDate: "2022-02-25", stillPath: nil),
        ])
        let app = AppState(store: LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), tmdb: stub)
        app.addToLibrary(sampleTitle())

        await app.refreshTitle("tv-100")

        XCTAssertNotNil(app.library.titles["tv-100"]?.lastRefreshed)
        XCTAssertEqual(app.library.episodes["tv-100"]?.count, 2)
        XCTAssertEqual(stub.tvDetailCallCount, 1)
        XCTAssertEqual(stub.seasonCallNumbers, [1])
    }

    func testFetchPreviewTitleReturnsMappedTitleWithoutAddingToLibrary() async {
        let stub = StubTMDBClient()
        stub.tvDetailResult = TMDBTVDetail(
            id: 100, name: "Severance", overview: "innie", posterPath: nil, firstAirDate: "2022-02-18",
            status: "Returning Series",
            seasons: [TMDBSeasonSummary(seasonNumber: 1, episodeCount: 2, airDate: nil)]
        )
        let app = AppState(store: LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), tmdb: stub)

        let preview = await app.fetchPreviewTitle(tmdbID: 100, mediaType: .tv)

        XCTAssertEqual(preview?.id, "tv-100")
        XCTAssertEqual(preview?.name, "Severance")
        XCTAssertTrue(app.library.entries.isEmpty, "preview must not add to library")
        XCTAssertEqual(stub.tvDetailCallCount, 1)
    }

    func testRunFullRefreshUpdatesStaleTitleAndReportsNoError() async {
        let stub = StubTMDBClient()
        stub.tvDetailResult = TMDBTVDetail(
            id: 100, name: "Severance", overview: nil, posterPath: nil, firstAirDate: nil,
            status: nil, seasons: [TMDBSeasonSummary(seasonNumber: 1, episodeCount: 1, airDate: nil)]
        )
        stub.seasons[1] = TMDBSeason(seasonNumber: 1, episodes: [
            TMDBTVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Good News", overview: nil, airDate: "2099-01-01", stillPath: nil)
        ])
        let app = AppState(
            store: LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            tmdb: stub,
            notifications: NotificationScheduler(client: MockNotificationClient())
        )
        app.addToLibrary(sampleTitle())

        await app.runFullRefresh()

        XCTAssertNotNil(app.library.titles["tv-100"]?.lastRefreshed)
        XCTAssertNil(app.lastRefreshError)
        XCTAssertEqual(stub.tvDetailCallCount, 1)
    }

    private func episodes(_ numbers: ClosedRange<Int>) -> [Episode] {
        numbers.map {
            Episode(tmdbID: 100, seasonNumber: 1, episodeNumber: $0, name: "E\($0)",
                    overview: nil, airDate: nil, stillPath: nil)
        }
    }

    func testSetEpisodesWatchedMarksAndUnmarksInBulk() {
        let app = makeSUT()
        let season = episodes(1...3)

        app.setEpisodesWatched(true, episodes: season, titleID: "tv-100")
        XCTAssertEqual(app.library.watchedEpisodes, Set(season.map(\.id)))

        app.setEpisodesWatched(false, episodes: Array(season.prefix(2)), titleID: "tv-100")
        XCTAssertEqual(app.library.watchedEpisodes, [season[2].id])
    }

    func testSetEpisodesWatchedIgnoresEmptyInput() {
        let app = makeSUT()
        app.setEpisodesWatched(true, episodes: [], titleID: "tv-100")
        XCTAssertTrue(app.library.watchedEpisodes.isEmpty)
    }

    func testSetEpisodeWatchedDelegatesToBulk() {
        let app = makeSUT()
        let only = episodes(1...1)[0]

        app.setEpisodeWatched(true, episode: only, titleID: "tv-100")
        XCTAssertEqual(app.library.watchedEpisodes, [only.id])

        app.setEpisodeWatched(false, episode: only, titleID: "tv-100")
        XCTAssertTrue(app.library.watchedEpisodes.isEmpty)
    }

    func testRemoveFromLibraryClearsWatchedEpisodes() {
        let app = makeSUT()
        app.addToLibrary(sampleTitle())
        let season = episodes(1...3)
        app.library.episodes["tv-100"] = season
        app.setEpisodesWatched(true, episodes: season, titleID: "tv-100")

        app.removeFromLibrary("tv-100")

        XCTAssertTrue(app.library.watchedEpisodes.isEmpty)
    }
}
