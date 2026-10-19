import XCTest
import UserNotifications
@testable import Airpisode

final class NotificationActionTests: XCTestCase {
    private let now = TMDBMapper.parseDate("2026-10-16")!  // noon UTC

    private func title(_ id: Int, _ type: MediaType) -> Title {
        Title(tmdbID: id, mediaType: type, name: "Severance", overview: "", posterPath: nil,
              firstAirDate: nil, tvStatus: nil, seasons: [], lastRefreshed: nil)
    }

    // MARK: - Content tagging

    func testEpisodeAlertCarriesCategoryAndUserInfoForBannerActions() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let episode = Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                              overview: nil, airDate: now.addingTimeInterval(30 * 3600 + 900), stillPath: nil)

        await scheduler.schedule(
            for: title(100, .tv),
            episodes: [episode],
            prefs: NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: nil, permissionRequested: true),
            now: now
        )

        let request = mock.addCalls.first
        XCTAssertEqual(request?.content.categoryIdentifier, NotificationScheduler.episodeCategory)
        XCTAssertEqual(request?.content.userInfo["kind"] as? String, "episode")
        XCTAssertEqual(request?.content.userInfo["titleID"] as? String, "tv-100")
        XCTAssertEqual(request?.content.userInfo["key"] as? String, episode.id)
    }

    func testMovieAlertCarriesCategoryAndUserInfoForBannerActions() async {
        let mock = MockNotificationClient()
        let scheduler = NotificationScheduler(client: mock)
        let release = MovieRelease(tmdbID: 200, kind: .digital, region: "US",
                                   date: now.addingTimeInterval(72 * 3600), hasTime: true)

        await scheduler.schedule(
            for: title(200, .movie),
            movieReleases: [release],
            prefs: NotificationPreferences(preAlertHours: 24, imminentAlertMinutes: nil, permissionRequested: true),
            now: now
        )

        let request = mock.addCalls.first
        XCTAssertEqual(request?.content.categoryIdentifier, NotificationScheduler.movieCategory)
        XCTAssertEqual(request?.content.userInfo["kind"] as? String, "movie")
        XCTAssertEqual(request?.content.userInfo["titleID"] as? String, "movie-200")
        XCTAssertEqual(request?.content.userInfo["key"] as? String, release.id)
    }

    // MARK: - Action routing through AppState

    @MainActor
    private func makeApp() -> (AppState, MockNotificationClient) {
        let mock = MockNotificationClient()
        let app = AppState(
            store: LibraryStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            notifications: NotificationScheduler(client: mock)
        )
        return (app, mock)
    }

    @MainActor
    func testMarkWatchedActionMarksTheEpisodeWatched() async {
        let (app, _) = makeApp()
        let episode = Episode(tmdbID: 100, seasonNumber: 2, episodeNumber: 5, name: "Woe's Hollow",
                              overview: nil, airDate: now.addingTimeInterval(24 * 3600), stillPath: nil)
        app.addToLibrary(title(100, .tv))
        app.library.episodes["tv-100"] = [episode]

        app.handleNotificationAction(
            identifier: NotificationScheduler.markWatchedAction, titleID: "tv-100", kind: "episode", key: episode.id
        )

        XCTAssertTrue(app.library.watchedEpisodes.contains(episode.id))
    }

    @MainActor
    func testMarkWatchedAndMuteActionsHandleMovies() async {
        let (app, _) = makeApp()
        app.addToLibrary(title(200, .movie))

        app.handleNotificationAction(
            identifier: NotificationScheduler.markWatchedAction, titleID: "movie-200", kind: "movie", key: nil
        )
        XCTAssertTrue(app.library.watchedMovies.contains("movie-200"))

        app.handleNotificationAction(
            identifier: NotificationScheduler.muteTitleAction, titleID: "movie-200", kind: "movie", key: nil
        )
        XCTAssertEqual(app.library.entries.first?.alertsMuted, true)
    }

    @MainActor
    func testUnknownActionIdentifierIsIgnored() async {
        let (app, _) = makeApp()
        app.addToLibrary(title(100, .tv))

        app.handleNotificationAction(identifier: "somethingElse", titleID: "tv-100", kind: "episode", key: nil)

        XCTAssertTrue(app.library.watchedEpisodes.isEmpty)
        XCTAssertEqual(app.library.entries.first?.alertsMuted, nil)
    }
}
