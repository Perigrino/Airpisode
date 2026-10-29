import SwiftUI

struct MyShowsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedID: String?
    @State private var pendingRemoval: Title?
    @SceneStorage("shows.search") private var searchText = ""
    @AppStorage("shows.filter") private var filterRaw = Library.ShowFilter.all.rawValue
    @AppStorage("shows.sort") private var sortRaw = Library.LibrarySort.name.rawValue

    private var filter: Library.ShowFilter {
        Library.ShowFilter(rawValue: filterRaw) ?? .all
    }

    private var sort: Library.LibrarySort {
        Library.LibrarySort(rawValue: sortRaw) ?? .name
    }

    private var trackedCount: Int {
        appState.library.entries.filter { $0.mediaType == .tv }.count
    }

    private var shows: [Title] {
        appState.library.orderedWithPinnedFirst(
            appState.library.queryShows(searchText: searchText, filter: filter, sort: sort)
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Space.s) {
                    if trackedCount == 0 {
                        EmptyState(
                            systemImage: "tv",
                            title: "No shows yet",
                            message: "Track a show and every new episode appears in To Watch before it airs.",
                            actionTitle: "Find shows"
                        ) {
                            appState.selectedSection = .discover
                        }
                    } else if shows.isEmpty {
                        EmptyState(
                            systemImage: "line.3.horizontal.decrease.circle",
                            title: "No shows match",
                            message: "Try a different search, or show everything again.",
                            actionTitle: "Clear search and filters"
                        ) {
                            clearFilters()
                        }
                    } else {
                        ForEach(shows) { title in
                            card(title).id(title.id)
                        }
                    }
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            // Snap the expanded card to the top so its details are fully in view.
            .onChange(of: expandedID) { newValue in
                guard let id = newValue else { return }
                withAnimation(Motion.smooth) { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search shows")
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "show")?",
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
            Text("Its episodes and watch history will be removed from this Mac.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.selectedSection = .discover
            } label: {
                Label("Add Show", systemImage: "plus")
            }
            .help("Find a show to track (⌘N)")

            Menu {
                Picker("Sort by", selection: sortBinding) {
                    ForEach(Library.LibrarySort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort shows")

            Menu {
                Picker("Show", selection: filterBinding) {
                    ForEach(Library.ShowFilter.allCases) { option in
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
            .help("Filter shows")
        }
    }

    private var filterBinding: Binding<Library.ShowFilter> {
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
                    badge: appState.library.isMuted(title.id) ? "Alerts muted" : nil
                )
            }
            .buttonStyle(.plain)
            .contextMenu { menu(for: title) }

            if expandedID == title.id {
                Divider()
                    .padding(.horizontal, Theme.Space.m)
                TitleDetailContent(tmdbID: title.tmdbID, mediaType: .tv, name: title.name)
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
            appState.setAlertsMuted(!appState.library.isMuted(title.id), titleID: title.id)
        } label: {
            Label(
                appState.library.isMuted(title.id) ? "Unmute alerts" : "Mute alerts",
                systemImage: appState.library.isMuted(title.id) ? "bell" : "bell.slash"
            )
        }
        Menu("Pre-release alert") {
            ForEach(AlertOverride.allCases) { option in
                Button {
                    appState.setPreAlertOverride(option, titleID: title.id)
                } label: {
                    if preAlertOverride(for: title.id) == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
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
        filterRaw = Library.ShowFilter.all.rawValue
    }

    private func preAlertOverride(for titleID: String) -> AlertOverride {
        appState.library.entries.first(where: { $0.id == titleID })?.preAlertOverride ?? .inherit
    }

    private func nextLabel(for title: Title) -> String? {
        if let episode = appState.library.nextEpisode(forTitle: title.id),
           let date = episode.airTimestamp ?? episode.airDate {
            let when = DateText.upcoming(date, includeTime: episode.airTimestamp != nil)
            return "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(when)"
        }
        // Season gap: the current season is over, but TMDB may already know the next
        // airing — often the premiere of a season months away.
        if let airing = title.nextAiring, let date = airing.airDate, date >= .now {
            let when = DateText.upcoming(date)
            if airing.episodeNumber == 1 {
                return "Season \(airing.seasonNumber) · \(when)"
            }
            return "S\(airing.seasonNumber)E\(airing.episodeNumber) · \(when)"
        }
        if let status = title.tvStatus, status == "Ended" || status == "Canceled" {
            return status
        }
        return nil
    }
}
