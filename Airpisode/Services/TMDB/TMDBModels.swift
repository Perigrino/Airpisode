import Foundation

struct TMDBSearchResponse: Decodable {
    let results: [TMDBSearchResult]
}

struct TMDBSearchResult: Decodable, Identifiable {
    let id: Int
    let mediaType: String            // "movie" | "tv" | "person"
    let name: String?                // tv
    let title: String?               // movie
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?        // tv "YYYY-MM-DD"
    let releaseDate: String?         // movie
    var popularity: Double? = nil
    var voteAverage: Double? = nil
    var voteCount: Int? = nil
    var displayName: String { name ?? title ?? "" }
    /// Identity across media types — a movie and a tv can share a TMDB id.
    var uniqueID: String { "\(mediaType)-\(id)" }
    enum CodingKeys: String, CodingKey {
        case id, name, title, overview, popularity
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}

struct TMDBTVDetail: Decodable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let status: String?
    let seasons: [TMDBSeasonSummary]
    var nextEpisodeToAir: TMDBTVEpisode? = nil
    enum CodingKeys: String, CodingKey {
        case id, name, overview, status, seasons
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case nextEpisodeToAir = "next_episode_to_air"
    }
}
struct TMDBSeasonSummary: Decodable {
    let seasonNumber: Int
    let episodeCount: Int
    let airDate: String?
    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case airDate = "air_date"
    }
}
struct TMDBSeason: Decodable {
    let seasonNumber: Int
    let episodes: [TMDBTVEpisode]
    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodes
    }
}
struct TMDBTVEpisode: Decodable {
    let episodeNumber: Int
    let seasonNumber: Int
    let name: String
    let overview: String?
    let airDate: String?
    let stillPath: String?
    enum CodingKeys: String, CodingKey {
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case name, overview
        case airDate = "air_date"
        case stillPath = "still_path"
    }
}
struct TMDBMovieDetail: Decodable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
    }
}
struct TMDBRecommendationsResponse: Decodable {
    let results: [TMDBRecommendation]
}
struct TMDBRecommendation: Decodable {
    let id: Int
    let name: String?                // tv
    let title: String?               // movie
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let releaseDate: String?
    var popularity: Double? = nil
    var voteAverage: Double? = nil
    var voteCount: Int? = nil
    enum CodingKeys: String, CodingKey {
        case id, name, title, overview, popularity
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}
struct TMDBCreditsResponse: Decodable {
    let cast: [TMDBCastMember]
}
struct TMDBCastMember: Decodable, Identifiable {
    let id: Int                      // person id
    let name: String
    let character: String?
    let profilePath: String?
    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }
}
/// Basic person data for the cast popover (`GET /person/{id}`).
struct TMDBPersonDetail: Decodable {
    let name: String
    var profilePath: String? = nil
    var knownForDepartment: String? = nil
    var birthday: String? = nil
    var deathday: String? = nil
    var placeOfBirth: String? = nil
    var biography: String? = nil
    enum CodingKeys: String, CodingKey {
        case name
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case birthday, deathday
        case placeOfBirth = "place_of_birth"
        case biography
    }
}
struct TMDBReleaseDatesResponse: Decodable {
    let id: Int
    let results: [TMDBRegionReleases]
}
struct TMDBRegionReleases: Decodable {
    let iso3166_1: String
    let releaseDates: [TMDBReleaseDate]
    enum CodingKeys: String, CodingKey {
        case iso3166_1 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}
struct TMDBReleaseDate: Decodable {
    let certification: String?
    let releaseDate: String          // full ISO datetime or "YYYY-MM-DD"
    let type: Int                    // 1 theatrical, 2 digital, 3 physical, 4 TV
    enum CodingKeys: String, CodingKey {
        case certification, type
        case releaseDate = "release_date"
    }
}
