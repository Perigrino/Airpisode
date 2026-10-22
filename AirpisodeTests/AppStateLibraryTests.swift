import XCTest
@testable import Airpisode

@MainActor
final class AppStateLibraryTests: XCTestCase {
    private func makeSUT() -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return AppState(store: LibraryStore(directory: dir), tmdb: StubTMDBClient())
    }

    private func makeSUT(tmdb: StubTMDBClient) -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return AppState(store: LibraryStore(directory: dir), tmdb: tmdb)
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

    func testSetEpisodesWatchedRecordsTimestampAndUnwatchRemovesIt() {
        let app = makeSUT()
        let episode = episodes(1...1)[0]

        app.setEpisodesWatched(true, episodes: [episode], titleID: "tv-100")
        let record = app.library.watchLog.first { $0.itemID == episode.id }
        XCTAssertEqual(record?.kind, .episode)
        XCTAssertEqual(record?.titleID, "tv-100")
        XCTAssertNotNil(record?.watchedAt)

        app.setEpisodesWatched(false, episodes: [episode], titleID: "tv-100")
        XCTAssertFalse(app.library.watchLog.contains { $0.itemID == episode.id })
    }

    func testSetMovieWatchedRecordsTimestampAndUnwatchRemovesIt() {
        let app = makeSUT()
        app.addToLibrary(sampleTitle(tmdbID: 200, mediaType: .movie))

        app.setMovieWatched(true, titleID: "movie-200")
        XCTAssertEqual(app.library.watchLog.first?.kind, .movie)
        XCTAssertEqual(app.library.watchLog.first?.titleID, "movie-200")
        XCTAssertNotNil(app.library.watchLog.first?.watchedAt)

        app.setMovieWatched(false, titleID: "movie-200")
        XCTAssertTrue(app.library.watchLog.isEmpty)
    }

    func testRemoveDeletesWatchLogRecords() {
        let app = makeSUT()
        app.addToLibrary(sampleTitle())
        app.library.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s1e1", watchedAt: Date())
        ]

        app.removeFromLibrary("tv-100")

        XCTAssertTrue(app.library.watchLog.isEmpty)
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

    func testRefreshTitleCapturesNextAiring() async {
        let stub = StubTMDBClient()
        stub.tvDetailResult = TMDBTVDetail(
            id: 100, name: "Severance", overview: nil, posterPath: nil, firstAirDate: nil,
            status: "Hiatus",
            seasons: [TMDBSeasonSummary(seasonNumber: 1, episodeCount: 2, airDate: nil)],
            nextEpisodeToAir: TMDBTVEpisode(
                episodeNumber: 3, seasonNumber: 3, name: "Episode 3",
                overview: nil, airDate: "2099-01-15", stillPath: nil
            )
        )
        stub.seasons[1] = TMDBSeason(seasonNumber: 1, episodes: [
            TMDBTVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Good News", overview: nil, airDate: "2022-02-18", stillPath: nil),
            TMDBTVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Half Loop", overview: nil, airDate: "2022-02-25", stillPath: nil),
        ])
        let app = AppState(store: LibraryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), tmdb: stub)
        app.addToLibrary(sampleTitle())

        await app.refreshTitle("tv-100")

        let airing = app.library.titles["tv-100"]?.nextAiring
        XCTAssertEqual(airing?.seasonNumber, 3)
        XCTAssertEqual(airing?.episodeNumber, 3)
        XCTAssertEqual(airing?.name, "Episode 3")
    }

    func testFetchPersonReturnsDetailFromClient() async {
        let stub = StubTMDBClient()
        stub.personResult = TMDBPersonDetail(
            name: "Adam Scott",
            profilePath: nil,
            knownForDepartment: "Acting",
            birthday: "1973-04-03",
            deathday: nil,
            placeOfBirth: "Santa Cruz, California, USA",
            biography: "Known for comedy."
        )
        let app = makeSUT(tmdb: stub)

        let person = await app.fetchPerson(tmdbID: 5)

        XCTAssertEqual(person?.name, "Adam Scott")
        XCTAssertEqual(person?.knownForDepartment, "Acting")
        XCTAssertEqual(person?.placeOfBirth, "Santa Cruz, California, USA")
        XCTAssertEqual(stub.personCallCount, 1)
    }

    func testSetEpisodesWatchedUpdatesDailySummary() {
        let app = makeSUT()
        let episode = episodes(1...1)[0]

        app.setEpisodesWatched(true, episodes: [episode], titleID: "tv-100")
        XCTAssertEqual(app.library.watchDays.count, 1)
        XCTAssertEqual(app.library.watchDays.first?.episodes, 1)
        XCTAssertEqual(app.library.watchDays.first?.movies, 0)

        app.setEpisodesWatched(false, episodes: [episode], titleID: "tv-100")
        XCTAssertTrue(app.library.watchDays.isEmpty)
    }

    func testSetMovieWatchedUpdatesDailySummary() {
        let app = makeSUT()
        app.addToLibrary(sampleTitle(tmdbID: 200, mediaType: .movie))

        app.setMovieWatched(true, titleID: "movie-200")
        XCTAssertEqual(app.library.watchDays.count, 1)
        XCTAssertEqual(app.library.watchDays.first?.episodes, 0)
        XCTAssertEqual(app.library.watchDays.first?.movies, 1)

        app.setMovieWatched(false, titleID: "movie-200")
        XCTAssertTrue(app.library.watchDays.isEmpty)
    }

    func testRemoveFromLibraryRemovesDailySummaryContribution() {
        let app = makeSUT()
        app.addToLibrary(sampleTitle())
        app.library.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s1e1", watchedAt: Date())
        ]
        app.library.rebuildWatchSummary()
        XCTAssertEqual(app.library.watchDays.count, 1)

        app.removeFromLibrary("tv-100")

        XCTAssertTrue(app.library.watchDays.isEmpty)
        XCTAssertEqual(app.library.undatedWatchCount, 0)
    }

    func testWatchMutationPrunesOldDiaryDetailButKeepsStats() {
        let app = makeSUT()
        let old = Date().addingTimeInterval(-8 * 86_400)
        app.library.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s1e1", watchedAt: old)
        ]
        app.library.rebuildWatchSummary()

        app.setMovieWatched(false, titleID: "movie-200")

        XCTAssertFalse(app.library.watchLog.contains { $0.itemID == "100-s1e1" })
        XCTAssertEqual(app.library.watchDays.count, 1, "pruning keeps the aggregate")
    }

    func testLoadLibraryPrunesOldDiaryDetail() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(directory: dir)
        var library = Library()
        library.titles["tv-100"] = sampleTitle()
        let old = Date().addingTimeInterval(-8 * 86_400)
        library.watchLog = [
            WatchRecord(kind: .episode, titleID: "tv-100", itemID: "100-s1e1", watchedAt: old)
        ]
        library.rebuildWatchSummary()
        try await store.save(library)

        let app = AppState(
            store: store,
            tmdb: StubTMDBClient(),
            notifications: NotificationScheduler(client: MockNotificationClient())
        )
        await app.loadLibrary()

        XCTAssertFalse(app.library.watchLog.contains { $0.itemID == "100-s1e1" })
        XCTAssertEqual(app.library.watchDays.count, 1)
    }
}
