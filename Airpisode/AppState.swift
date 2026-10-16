import SwiftUI

enum Secrets {
    static var tmdbKey: String {
        Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String ?? ""
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var library = Library()
    @Published var lastRefreshError: String?

    let tmdb: TMDBClientProtocol
    private let store: LibraryStore

    init(store: LibraryStore = LibraryStore(), tmdb: TMDBClientProtocol = TMDBClient(apiKey: Secrets.tmdbKey)) {
        self.store = store
        self.tmdb = tmdb
    }

    func loadLibrary() async {
        library = await store.load()
    }

    // MARK: - Library mutations

    func addToLibrary(_ title: Title) {
        guard !library.entries.contains(where: { $0.id == title.id }) else { return }
        library.titles[title.id] = title
        library.entries.append(
            WatchlistEntry(tmdbID: title.tmdbID, mediaType: title.mediaType, addedAt: Date(), isTrackingEnabled: true)
        )
        save()
    }

    func removeFromLibrary(_ titleID: String) {
        // TODO(Task 9): cancel this title's pending notifications here.
        library.entries.removeAll { $0.id == titleID }
        library.titles.removeValue(forKey: titleID)
        library.episodes.removeValue(forKey: titleID)
        library.movieReleases.removeValue(forKey: titleID)
        library.watchedShows.remove(titleID)
        library.watchedMovies.remove(titleID)
        save()
    }

    // MARK: - Refresh

    func refreshTitle(_ titleID: String) async {
        guard let entry = library.entries.first(where: { $0.id == titleID }) else { return }
        do {
            switch entry.mediaType {
            case .tv:
                let detail = try await tmdb.tvDetail(id: entry.tmdbID)
                var title = TMDBMapper.title(from: detail)
                var episodes: [Episode] = []
                for season in detail.seasons where season.seasonNumber > 0 {
                    let seasonData = try await tmdb.season(tvID: entry.tmdbID, season: season.seasonNumber)
                    episodes += TMDBMapper.episodes(seasonData, tvID: entry.tmdbID)
                }
                title.lastRefreshed = Date()
                library.titles[titleID] = title
                library.episodes[titleID] = episodes
            case .movie:
                let detail = try await tmdb.movieDetail(id: entry.tmdbID)
                var title = TMDBMapper.title(from: detail)
                let releases = try await tmdb.movieReleaseDates(id: entry.tmdbID)
                let region = UserDefaults.standard.string(forKey: "defaultRegion") ?? "US"
                title.lastRefreshed = Date()
                library.titles[titleID] = title
                library.movieReleases[titleID] = TMDBMapper.movieReleases(releases, movieID: entry.tmdbID, region: region)
            }
            lastRefreshError = nil
            try? await store.save(library)
        } catch {
            lastRefreshError = "Couldn't refresh \(library.titles[titleID]?.name ?? titleID): \(error.localizedDescription)"
        }
    }

    private func save() {
        let snapshot = library
        Task { try? await store.save(snapshot) }
    }
}
