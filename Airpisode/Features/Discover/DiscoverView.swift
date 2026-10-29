import SwiftUI

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [TMDBSearchResult] = []
    @Published var recommendations: [TMDBSearchResult] = []
    @Published var recommendationReason: String?
    @Published var isSearching = false
    @Published var errorMessage: String?

    private let client: TMDBClientProtocol

    init(client: TMDBClientProtocol) {
        self.client = client
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search() async {
        let trimmed = trimmedQuery
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
            errorMessage = "Couldn't search. Check your connection and try again."
        }
        isSearching = false
    }

    /// Blends several tracked titles into a ranked suggestion list.
    func loadRecommendations(library: Library) async {
        let suggestion = await RecommendationEngine(client: client).suggestions(for: library)
        recommendations = suggestion.items
        recommendationReason = Self.reason(for: suggestion.seedNames)
    }

    private static func reason(for seeds: [String]) -> String? {
        guard let first = seeds.first else { return nil }
        return seeds.count == 1 ? "Because you're tracking \(first)" : "Based on your watchlist"
    }
}

enum DiscoverFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case tv = "Shows"
    case movies = "Movies"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Results"
        case .tv: return "Shows"
        case .movies: return "Movies"
        }
    }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                    content
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            // Snap the expanded card to the top so its details are fully in view.
            .onChange(of: expandedID) { newValue in
                guard let id = newValue else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .searchable(text: $viewModel.query, placement: .toolbar, prompt: "Search shows, movies, and people")
        .toolbar { toolbarContent }
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

    @ViewBuilder
    private var content: some View {
        if viewModel.trimmedQuery.isEmpty {
            recommendations
        } else {
            searchResults
        }
    }

    @ViewBuilder
    private var recommendations: some View {
        if viewModel.recommendations.isEmpty {
            EmptyState(
                systemImage: "sparkle.magnifyingglass",
                title: appState.library.entries.isEmpty ? "Find something to watch" : "Nothing to suggest yet",
                message: appState.library.entries.isEmpty
                    ? "Search for a show or movie, then add it to your library to track new episodes and releases."
                    : "Add a few more titles and suggestions will appear here."
            )
        } else {
            SectionHeader(
                title: viewModel.recommendationReason ?? "Suggested for you",
                count: filtered(viewModel.recommendations).count
            )
            .padding(.top, Theme.Space.xs)

            ForEach(filtered(viewModel.recommendations), id: \.uniqueID) { result in
                discoverRow(result).id(rowID(result))
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let error = viewModel.errorMessage {
            InlineBanner(
                message: error,
                tone: .error,
                actionTitle: "Try Again"
            ) {
                Task { await viewModel.search() }
            }
        } else if viewModel.results.isEmpty && viewModel.isSearching {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonRow()
            }
        } else if filtered(viewModel.results).isEmpty {
            EmptyState(
                systemImage: "magnifyingglass",
                title: "No matches for “\(viewModel.trimmedQuery)”",
                message: filter == .all
                    ? "Check the spelling, or try the show's original title."
                    : "Try a different search, or show all results."
            )
        } else {
            SectionHeader(title: filter.label, count: filtered(viewModel.results).count)
                .padding(.top, Theme.Space.xs)

            ForEach(filtered(viewModel.results), id: \.uniqueID) { result in
                discoverRow(result).id(rowID(result))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Filter", selection: $filter) {
                ForEach(DiscoverFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Limit results to shows or movies")
        }
    }

    private func rowID(_ result: TMDBSearchResult) -> String {
        "\(mediaType(of: result).rawValue)-\(result.id)"
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
                Divider()
                    .padding(.horizontal, Theme.Space.m)
                TitleDetailContent(tmdbID: result.id, mediaType: mediaType(of: result), name: result.displayName)
                    .padding(Theme.Space.m)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(PosterTintedCard(posterPath: result.posterPath, cornerRadius: Theme.Radius.l))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
    }

    private func mediaType(of result: TMDBSearchResult) -> MediaType {
        result.mediaType == "movie" ? .movie : .tv
    }
}
