import Foundation
@testable import Airpisode

/// In-memory air-time provider for release-engine tests.
final class StubAirTimeProvider: AirTimeProviding, @unchecked Sendable {
    var timestamps: [EpisodeKey: Date] = [:]
    var requests: [AirTimeRequest] = []

    func airTimestamps(for show: AirTimeRequest, episodes: [Episode]) async -> [EpisodeKey: Date] {
        requests.append(show)
        return timestamps
    }
}
