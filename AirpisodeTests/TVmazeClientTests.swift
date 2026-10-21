import XCTest
@testable import Airpisode

final class TVmazeClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func response(_ url: URL, status: Int = 200, body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }

    func testMapsAirstampsBySeasonAndEpisode() async {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.path {
            case "/lookup/shows":
                return self.response(url, body: #"{"id":55350,"name":"Abbott Elementary"}"#)
            case "/shows/55350/episodes":
                return self.response(url, body: """
                [
                  {"season":6,"number":3,"airstamp":"2026-10-22T00:30:00+00:00"},
                  {"season":6,"number":4,"airstamp":null}
                ]
                """)
            default:
                throw URLError(.badURL)
            }
        }

        let client = TVmazeClient(session: MockURLProtocol.session(), minimumInterval: 0)
        let show = AirTimeRequest(tvdbID: 402910, imdbID: nil)
        let times = await client.airTimestamps(for: show, episodes: [])

        XCTAssertEqual(
            times[EpisodeKey(season: 6, number: 3)],
            TMDBMapper.parseDateTime("2026-10-22T00:30:00+00:00")
        )
        XCTAssertNil(times[EpisodeKey(season: 6, number: 4)])
    }

    func testFallsBackToIMDbWhenTVDBLookupMisses() async {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if url.path == "/lookup/shows" {
                if query.contains(where: { $0.name == "thetvdb" }) {
                    return self.response(url, status: 404, body: "")
                }
                return self.response(url, body: #"{"id":46562,"name":"The Last of Us"}"#)
            }
            if url.path == "/shows/46562/episodes" {
                return self.response(url, body: #"[{"season":2,"number":1,"airstamp":"2025-04-13T01:00:00+00:00"}]"#)
            }
            throw URLError(.badURL)
        }

        let client = TVmazeClient(session: MockURLProtocol.session(), minimumInterval: 0)
        let show = AirTimeRequest(tvdbID: 99, imdbID: "tt3581920")
        let times = await client.airTimestamps(for: show, episodes: [])

        XCTAssertEqual(
            times[EpisodeKey(season: 2, number: 1)],
            TMDBMapper.parseDateTime("2025-04-13T01:00:00+00:00")
        )
    }

    func testMissingScheduleReturnsNoTimestamps() async {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            throw URLError(.notConnectedToInternet)
        }

        let client = TVmazeClient(session: MockURLProtocol.session(), minimumInterval: 0)
        let show = AirTimeRequest(tvdbID: 1, imdbID: nil)
        let times = await client.airTimestamps(for: show, episodes: [])

        XCTAssertTrue(times.isEmpty)
    }
}
