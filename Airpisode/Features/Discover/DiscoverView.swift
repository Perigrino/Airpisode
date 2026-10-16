import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [TMDBSearchResult] = []
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
}

struct DiscoverView: View {
    @StateObject private var viewModel: DiscoverViewModel

    init(client: TMDBClientProtocol = TMDBClient(apiKey: Secrets.tmdbKey)) {
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                placeholder("Search for a show or movie")
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
