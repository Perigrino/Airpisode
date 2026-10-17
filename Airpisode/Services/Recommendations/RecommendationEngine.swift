import Foundation

/// Builds "you might like" suggestions from the titles the user tracks.
///
/// Uses TMDB's `/recommendations` list (collaborative filtering) rather than `/similar`, blends
/// several seeds instead of one, and ranks each candidate by how many seeds agree and how high it
/// sits in each list. Already-tracked titles and thinly-voted noise are dropped.
struct RecommendationEngine {
    let client: TMDBClientProtocol
    /// Most recently added titles to seed from.
    var maxSeeds = 6
    var limit = 12
    /// Below this many votes a title is treated as noise, unless that leaves nothing.
    var minimumVoteCount = 50
    /// How far into each seed's list to look.
    var listDepth = 20

    struct Suggestion {
        let items: [TMDBSearchResult]
        let seedNames: [String]
    }

    func suggestions(for library: Library) async -> Suggestion {
        let seeds: [(entry: WatchlistEntry, title: Title)] = library.entries
            .sorted { $0.addedAt > $1.addedAt }
            .prefix(maxSeeds)
            .compactMap { entry in library.titles[entry.id].map { (entry, $0) } }
        guard !seeds.isEmpty else { return Suggestion(items: [], seedNames: []) }

        let trackedIDs = Set(library.entries.map(\.id))
        let client = self.client
        let depth = listDepth
        var candidates: [String: (item: TMDBSearchResult, score: Double)] = [:]
        // Filled by seed index so the order stays deterministic regardless of task completion order.
        var seedNames = [String?](repeating: nil, count: seeds.count)

        await withTaskGroup(of: (Int, String, [TMDBSearchResult]).self) { group in
            for (index, seed) in seeds.enumerated() {
                group.addTask {
                    var items = (try? await client.recommendations(mediaType: seed.entry.mediaType,
                                                                   tmdbID: seed.entry.tmdbID)) ?? []
                    if items.isEmpty {
                        items = (try? await client.similar(mediaType: seed.entry.mediaType,
                                                           tmdbID: seed.entry.tmdbID)) ?? []
                    }
                    return (index, seed.title.name, items)
                }
            }
            for await (index, name, items) in group {
                seedNames[index] = name
                // A more recently added title weighs more.
                let seedWeight = 1.0 / Double(index + 1)
                for (rank, item) in items.prefix(depth).enumerated() {
                    guard item.mediaType != "person", !trackedIDs.contains(item.uniqueID) else { continue }
                    // Higher in a seed's list weighs more.
                    candidates[item.uniqueID, default: (item, 0)].score += seedWeight / Double(rank + 2)
                }
            }
        }

        var ranked = candidates.values
            .filter { ($0.item.voteCount ?? 0) >= minimumVoteCount }
            .sorted(by: Self.rank)
            .map(\.item)
        if ranked.isEmpty {
            // A niche watchlist can have few well-voted matches; show them anyway.
            ranked = candidates.values.sorted(by: Self.rank).map(\.item)
        }
        return Suggestion(items: Array(ranked.prefix(limit)), seedNames: seedNames.compactMap { $0 })
    }

    private static func rank(_ a: (item: TMDBSearchResult, score: Double),
                             _ b: (item: TMDBSearchResult, score: Double)) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return (a.item.voteAverage ?? 0) > (b.item.voteAverage ?? 0)
    }
}
