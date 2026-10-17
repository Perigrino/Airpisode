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

enum DiscoverFilter: String, CaseIterable {
    case all = "Best Match"
    case tv = "TV Shows"
    case movies = "Movies"
}

struct DiscoverView: View {
    @StateObject private var viewModel: DiscoverViewModel
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?
    @State private var filter: DiscoverFilter = .all

    init(client: TMDBClientProtocol = TMDBClient()) {
        _viewModel = StateObject(wrappedValue: DiscoverViewModel(client: client))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                PageHeader(title: "Discover",
                           subtitle: "Find your next favorite show or movie")
                filterChips

                if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if viewModel.recommendations.isEmpty {
                        placeholder(appState.library.entries.isEmpty
                                    ? "Search for a show or movie"
                                    : "No recommendations yet")
                    } else {
                        sectionTitle("Because you're tracking…")
                        ForEach(filtered(viewModel.recommendations)) { result in
                            discoverRow(result)
                        }
                    }
                } else if let error = viewModel.errorMessage {
                    placeholder(error)
                } else if viewModel.results.isEmpty && viewModel.isSearching {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonRow()
                    }
                } else if viewModel.results.isEmpty {
                    placeholder("No results")
                } else {
                    ForEach(filtered(viewModel.results)) { result in
                        discoverRow(result)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground()
        .searchable(text: $viewModel.query, prompt: "Search movies, shows, people…")
        .navigationTitle("Discover")
        .onChange(of: viewModel.query) { _ in
            withAnimation(Motion.quick) { expandedID = nil }
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

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(DiscoverFilter.allCases, id: \.self) { option in
                Button {
                    withAnimation(Motion.smooth) { filter = option }
                } label: {
                    Chip(text: option.rawValue, filled: filter == option)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(Motion.smooth, value: filter)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func filtered(_ results: [TMDBSearchResult]) -> [TMDBSearchResult] {
        switch filter {
        case .all: return results
        case .tv: return results.filter { $0.mediaType == "tv" }
        case .movies: return results.filter { $0.mediaType == "movie" }
        }
    }

    private func discoverRow(_ result: TMDBSearchResult) -> some View {
        let id = "\(mediaType(of: result).rawValue)-\(result.id)"
        let tracked = appState.library.entries.contains { $0.id == id }
        return VStack(spacing: 0) {
            Button {
                withAnimation(Motion.smooth) {
                    expandedID = expandedID == id ? nil : id
                }
            } label: {
                SearchRowView(result: result, isExpanded: expandedID == id, isTracked: tracked)
            }
            .buttonStyle(.plain)
            if expandedID == id {
                TitleDetailContent(tmdbID: result.id, mediaType: mediaType(of: result), name: result.displayName)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Motion.smooth) { expandedID = nil } }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.cardBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift()
    }

    private func mediaType(of result: TMDBSearchResult) -> MediaType {
        result.mediaType == "movie" ? .movie : .tv
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .appear()
    }
}
