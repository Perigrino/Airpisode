import SwiftUI

struct MyMoviesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?
    @State private var pendingRemoval: Title?
    @SceneStorage("movies.search") private var searchText = ""
    @AppStorage("movies.filter") private var filterRaw = Library.MovieFilter.all.rawValue
    @AppStorage("movies.sort") private var sortRaw = Library.LibrarySort.name.rawValue

    private var filter: Library.MovieFilter {
        Library.MovieFilter(rawValue: filterRaw) ?? .all
    }

    private var sort: Library.LibrarySort {
        Library.LibrarySort(rawValue: sortRaw) ?? .name
    }

    private var trackedCount: Int {
        appState.library.entries.filter { $0.mediaType == .movie }.count
    }

    private var movies: [Title] {
        appState.library.orderedWithPinnedFirst(
            appState.library.queryMovies(searchText: searchText, filter: filter, sort: sort)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Space.s) {
                    if trackedCount == 0 {
                        EmptyState(
                            systemImage: "film",
                            title: "No movies yet",
                            message: "Track a movie and every release date — theaters, digital, physical — appears in To Watch.",
                            actionTitle: "Find movies"
                        ) {
                            appState.selectedSection = .discover
                        }
                    } else if movies.isEmpty {
                        EmptyState(
                            systemImage: "line.3.horizontal.decrease.circle",
                            title: "No movies match",
                            message: "Try a different search, or show everything again.",
                            actionTitle: "Clear search and filters"
                        ) {
                            clearFilters()
                        }
                    } else {
                        ForEach(movies) { title in
                            card(title).id(title.id)
                        }
                    }
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .onChange(of: expandedID) { newValue in
                guard let id = newValue else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search movies")
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "movie")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let title = pendingRemoval {
                    appState.removeFromLibrary(title.id)
                    if expandedID == title.id { expandedID = nil }
                }
                pendingRemoval = nil
            }
            Button("Keep", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its release dates and watch history will be removed from this Mac.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Add Movie", systemImage: "plus")
            }
            .help("Find a movie to track (⌘N)")

            Menu {
                Picker("Sort by", selection: sortBinding) {
                    ForEach(Library.LibrarySort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort movies")

            Menu {
                Picker("Show", selection: filterBinding) {
                    ForEach(Library.MovieFilter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Label(
                    "Filter",
                    systemImage: filter == .all
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                )
            }
            .help("Filter movies")
        }
    }

    private var filterBinding: Binding<Library.MovieFilter> {
        Binding(get: { filter }, set: { filterRaw = $0.rawValue })
    }

    private var sortBinding: Binding<Library.LibrarySort> {
        Binding(get: { sort }, set: { sortRaw = $0.rawValue })
    }

    @ViewBuilder
    private func card(_ title: Title) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(Motion.smooth) {
                    expandedID = expandedID == title.id ? nil : title.id
                }
            } label: {
                TitleRowView(
                    title: title,
                    nextLabel: nextLabel(for: title),
                    isExpanded: expandedID == title.id,
                    badge: badge(for: title),
                    badgeIcon: appState.library.watchedMovies.contains(title.id)
                        ? "checkmark.circle" : "bell.slash"
                )
            }
            .buttonStyle(.plain)
            .contextMenu { menu(for: title) }

            if expandedID == title.id {
                Divider()
                    .padding(.horizontal, Theme.Space.m)
                TitleDetailContent(tmdbID: title.tmdbID, mediaType: .movie, name: title.name)
                    .padding(Theme.Space.m)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(PosterTintedCard(posterPath: title.posterPath, cornerRadius: Theme.Radius.l))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
    }

    @ViewBuilder
    private func menu(for title: Title) -> some View {
        Button {
            appState.setPinned(!appState.library.isPinned(title.id), titleID: title.id)
        } label: {
            Label(
                appState.library.isPinned(title.id) ? "Unpin" : "Pin to top",
                systemImage: appState.library.isPinned(title.id) ? "pin.slash" : "pin"
            )
        }
        Button {
            appState.setMovieWatched(
                !appState.library.watchedMovies.contains(title.id),
                titleID: title.id
            )
        } label: {
            Label(
                appState.library.watchedMovies.contains(title.id) ? "Mark unwatched" : "Mark watched",
                systemImage: appState.library.watchedMovies.contains(title.id) ? "arrow.uturn.backward" : "checkmark"
            )
        }
        Button {
            appState.setAlertsMuted(!appState.library.isMuted(title.id), titleID: title.id)
        } label: {
            Label(
                appState.library.isMuted(title.id) ? "Unmute alerts" : "Mute alerts",
                systemImage: appState.library.isMuted(title.id) ? "bell" : "bell.slash"
            )
        }
        Divider()
        Button(role: .destructive) {
            pendingRemoval = title
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func clearFilters() {
        searchText = ""
        filterRaw = Library.MovieFilter.all.rawValue
    }

    private func badge(for title: Title) -> String? {
        if appState.library.watchedMovies.contains(title.id) { return "Watched" }
        if appState.library.isMuted(title.id) { return "Alerts muted" }
        return nil
    }

    private func nextLabel(for title: Title) -> String? {
        if let release = (appState.library.movieReleases[title.id] ?? [])
            .filter({ ($0.date ?? .distantPast) >= .now })
            .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }),
           let date = release.date {
            let when = DateText.upcoming(date, includeTime: release.hasTime)
            return "\(release.kind.upcomingLabel) · \(when)"
        }
        // Not in the release-dates payload (nothing tracked there) — fall back to the
        // movie's own release date while it's still in the future.
        if let date = title.firstAirDate, date >= .now {
            return "Release · \(DateText.upcoming(date))"
        }
        return nil
    }
}
