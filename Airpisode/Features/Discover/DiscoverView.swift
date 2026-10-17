import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [TMDBSearchResult] = []
    @Published var recommendations: [TMDBSearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    private let client: TMDBClientProtocol

    init(client: TMDBClientProtocol) {
        self.client = client
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }
        isSearching = true
        do {
            let hits = try await client.searchMulti(query: trimmed)
            results = hits.filter { $0.mediaType != "person" }
            errorMessage = nil
        } catch is CancellationError {
            // Superseded by a newer keystroke; leave state alone.
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
        isSearching = false
    }

    /// "Because you're tracking…": recommendations from the most recently added tracked titles.
    func loadRecommendations(library: Library) async {
        let seeds = library.entries.sorted { $0.addedAt > $1.addedAt }.prefix(3)
        guard !seeds.isEmpty else {
            recommendations = []
            return
        }
        var seen = Set<String>()
        var picks: [TMDBSearchResult] = []
        for seed in seeds {
            guard let recs = try? await client.recommendations(mediaType: seed.mediaType, tmdbID: seed.tmdbID) else { continue }
            for rec in recs {
                let key = "\(rec.mediaType)-\(rec.id)"
                if seen.insert(key).inserted,
                   !library.entries.contains(where: { $0.id == key }) {
                    picks.append(rec)
                }
            }
        }
        recommendations = Array(picks.prefix(12))
    }
}

struct DiscoverView: View {
    @StateObject private var viewModel: DiscoverViewModel
    @EnvironmentObject private var appState: AppState

    init(client: TMDBClientProtocol = TMDBClient(apiKey: Secrets.tmdbKey)) {
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if viewModel.recommendations.isEmpty {
                    placeholder(appState.library.entries.isEmpty
                                ? "Search for a show or movie"
                                : "No recommendations yet")
                } else {
                    List {
                        Section("Because you're tracking…") {
                            ForEach(viewModel.recommendations) { result in
                                NavigationLink {
                                    TitleDetailView(tmdbID: result.id, mediaType: mediaType(of: result), name: result.displayName)
                                } label: {
                                    SearchRowView(result: result)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            } else if let error = viewModel.errorMessage {
                placeholder(error)
            } else if viewModel.results.isEmpty && !viewModel.isSearching {
                placeholder("No results")
            } else {
                List(viewModel.results) { result in
                    NavigationLink {
                        TitleDetailView(tmdbID: result.id, mediaType: mediaType(of: result), name: result.displayName)
                    } label: {
                        SearchRowView(result: result)
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $viewModel.query, prompt: "Title, show, or movie")
        .navigationTitle("Discover")
        .task(id: appState.library.entries.map(\.id).sorted().joined()) {
            await viewModel.loadRecommendations(library: appState.library)
        }
        .task(id: viewModel.query) {
            // Debounce: wait out rapid keystrokes, cancel on any query change.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.search()
        }
    }

    private func mediaType(of result: TMDBSearchResult) -> MediaType {
        result.mediaType == "movie" ? .movie : .tv
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
