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

    /// "Because you're tracking…": titles most similar to the most recently added tracked title.
    func loadRecommendations(library: Library) async {
        guard let seed = library.entries.max(by: { $0.addedAt < $1.addedAt }) else {
            recommendations = []
            return
        }
        guard let recs = try? await client.similar(mediaType: seed.mediaType, tmdbID: seed.tmdbID) else {
            recommendations = []
            return
        }
        recommendations = Array(recs.prefix(6))
    }
}

struct DiscoverView: View {
    @StateObject private var viewModel: DiscoverViewModel
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?

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
                                discoverRow(result)
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
                    discoverRow(result)
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $viewModel.query, prompt: "Title, show, or movie")
        .navigationTitle("Discover")
        .onChange(of: viewModel.query) { _ in
            withAnimation(.easeInOut(duration: 0.15)) { expandedID = nil }
        }
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

    private func discoverRow(_ result: TMDBSearchResult) -> some View {
        let id = "\(mediaType(of: result).rawValue)-\(result.id)"
        return Group {
            SearchRowView(result: result, isExpanded: expandedID == id)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedID = expandedID == id ? nil : id
                    }
                }
            if expandedID == id {
                TitleDetailContent(tmdbID: result.id, mediaType: mediaType(of: result), name: result.displayName)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
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
