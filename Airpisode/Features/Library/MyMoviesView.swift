import SwiftUI

struct MyMoviesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?
    @State private var searchText = ""
    @State private var movieFilter: Library.MovieFilter = .all
    @State private var sortBy: Library.LibrarySort = .name
    @FocusState private var searchFocused: Bool

    private var trackedMovies: [Title] {
        appState.library.entries
            .filter { $0.mediaType == .movie }
            .compactMap { appState.library.titles[$0.id] }
    }

    private var movies: [Title] {
        appState.library.orderedWithPinnedFirst(
            appState.library.queryMovies(searchText: searchText, filter: movieFilter, sort: sortBy)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    let tracked = trackedMovies
                    PageHeader(title: "My Movies",
                               subtitle: subtitle(trackedCount: tracked.count, visibleCount: movies.count))
                    if tracked.isEmpty {
                        emptyState
                    } else {
                        controls
                        if movies.isEmpty {
                            noMatches
                        } else {
                            ForEach(movies) { title in
                                card(title).id(title.id)
                            }
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, DockBar.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            // Snap the expanded card to the top so its details are fully in view.
            .onChange(of: expandedID) { newValue in
                guard let id = newValue else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .navigationTitle("My Movies")
        .toolbar {
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Add Movie", systemImage: "plus")
            }
            .help("Find a movie in Discover")
        }
    }

    @ViewBuilder
    private func card(_ title: Title) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(Motion.smooth) {
                    expandedID = expandedID == title.id ? nil : title.id
                }
            } label: {
                TitleRowView(title: title, nextLabel: nextLabel(for: title),
                             isExpanded: expandedID == title.id,
                             badge: appState.library.isMuted(title.id) ? "Muted" : nil)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    appState.setPinned(!appState.library.isPinned(title.id), titleID: title.id)
                } label: {
                    Label(appState.library.isPinned(title.id) ? "Unpin" : "Pin to top",
                          systemImage: "pin")
                }
                Button {
                    appState.setAlertsMuted(!appState.library.isMuted(title.id), titleID: title.id)
                } label: {
                    Label(appState.library.isMuted(title.id) ? "Unmute alerts" : "Mute alerts",
                          systemImage: appState.library.isMuted(title.id) ? "bell.fill" : "bell.slash")
                }
                Divider()
                Button(role: .destructive) {
                    appState.removeFromLibrary(title.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            if expandedID == title.id {
                TitleDetailContent(tmdbID: title.tmdbID, mediaType: .movie, name: title.name)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { collapse() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(PosterTintedCard(posterPath: title.posterPath))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hoverLift()
    }

    /// Search + sort + filter row. The invisible ⌘F button keeps search one shortcut away.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search movies", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .help("Filter by title (⌘F)")
                Menu {
                    Picker("Sort", selection: $sortBy) {
                        ForEach(Library.LibrarySort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                } label: {
                    Label(sortBy.label, systemImage: "arrow.up.arrow.down")
                }
                .fixedSize()
            }
            HStack(spacing: 6) {
                ForEach(Library.MovieFilter.allCases) { filter in
                    FilterChip(title: filter.label, isSelected: movieFilter == filter) {
                        movieFilter = filter
                    }
                }
            }
        }
        .background(
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    private func subtitle(trackedCount: Int, visibleCount: Int) -> String {
        if trackedCount == 0 { return "Track your first movie from Discover" }
        if visibleCount == trackedCount {
            return "\(trackedCount) movie\(trackedCount == 1 ? "" : "s") tracked"
        }
        return "\(visibleCount) of \(trackedCount) movie\(trackedCount == 1 ? "" : "s")"
    }

    private var noMatches: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.headline)
            Button("Clear search & filters") {
                searchText = ""
                movieFilter = .all
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No movies yet")
                .font(.headline)
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Find Movies in Discover", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .appear()
    }

    private func collapse() {
        withAnimation(Motion.smooth) { expandedID = nil }
    }

    private func nextLabel(for title: Title) -> String? {
        let releaseLabel = upcomingReleaseLabel(for: title)
        if releaseLabel != nil { return releaseLabel }
        // Not in the release-dates payload (nothing tracked there) — fall back to the
        // movie's own release date while it's still in the future.
        if let date = title.firstAirDate, date >= .now {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return "Release: \(formatter.string(from: date))"
        }
        return nil
    }

    private func upcomingReleaseLabel(for title: Title) -> String? {
        guard let release = (appState.library.movieReleases[title.id] ?? [])
            .filter({ ($0.date ?? .distantPast) >= .now })
            .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }),
              let date = release.date
        else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = release.hasTime ? "MMM d 'at' HH:mm" : "MMM d"
        return "\(release.kind.label): \(formatter.string(from: date))"
    }
}
