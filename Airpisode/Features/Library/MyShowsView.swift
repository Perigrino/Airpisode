import SwiftUI

struct MyShowsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?
    @State private var searchText = ""
    @State private var showFilter: Library.ShowFilter = .all
    @State private var sortBy: Library.LibrarySort = .name
    @FocusState private var searchFocused: Bool

    private var trackedShows: [Title] {
        appState.library.entries
            .filter { $0.mediaType == .tv }
            .compactMap { appState.library.titles[$0.id] }
    }

    private var shows: [Title] {
        appState.library.orderedWithPinnedFirst(
            appState.library.queryShows(searchText: searchText, filter: showFilter, sort: sortBy)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    let tracked = trackedShows
                    PageHeader(title: "My Shows",
                               subtitle: subtitle(trackedCount: tracked.count, visibleCount: shows.count))
                    if tracked.isEmpty {
                        emptyState
                    } else {
                        controls
                        if shows.isEmpty {
                            noMatches
                        } else {
                            ForEach(shows) { title in
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
        .navigationTitle("My Shows")
        .toolbar {
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Add Show", systemImage: "plus")
            }
            .help("Find a show in Discover")
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
                TitleDetailContent(tmdbID: title.tmdbID, mediaType: .tv, name: title.name)
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

    /// Search + sort + filter row. The invisible ⌘F button keeps search one shortcut away —
    /// the app's first keyboard shortcut.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search shows", text: $searchText)
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
                ForEach(Library.ShowFilter.allCases) { filter in
                    FilterChip(title: filter.label, isSelected: showFilter == filter) {
                        showFilter = filter
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
        if trackedCount == 0 { return "Track your first show from Discover" }
        if visibleCount == trackedCount {
            return "\(trackedCount) show\(trackedCount == 1 ? "" : "s") tracked"
        }
        return "\(visibleCount) of \(trackedCount) show\(trackedCount == 1 ? "" : "s")"
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
                showFilter = .all
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
            Image(systemName: "tv")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No shows yet")
                .font(.headline)
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Find Shows in Discover", systemImage: "plus.circle")
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
        if let episode = appState.library.nextEpisode(forTitle: title.id) {
            let when = episode.airDate.map { EpisodeRowView.dayFormatter.string(from: $0) } ?? "TBD"
            return "Next: S\(episode.seasonNumber)E\(episode.episodeNumber) · \(when)"
        }
        // Season gap: the current season is over, but TMDB may already know the next
        // airing — often the premiere of a season months away.
        if let airing = title.nextAiring, let date = airing.airDate, date >= .now {
            let when = EpisodeRowView.dayFormatter.string(from: date)
            if airing.episodeNumber == 1 {
                return "Season \(airing.seasonNumber) · \(when)"
            }
            return "Next: S\(airing.seasonNumber)E\(airing.episodeNumber) · \(when)"
        }
        return nil
    }
}
