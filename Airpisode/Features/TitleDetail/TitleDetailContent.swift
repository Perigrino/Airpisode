import SwiftUI

/// Inline detail content: embedded directly in lists, expanded/collapsed per row.
/// No outer ScrollView — the hosting list provides scrolling.
struct TitleDetailContent: View {
    let tmdbID: Int
    let mediaType: MediaType
    let name: String

    @EnvironmentObject private var appState: AppState
    @State private var selectedSeason: Int?
    @State private var previewTitle: Title?
    @State private var cast: [TMDBCastMember] = []
    @State private var selectedCastID: Int?
    @State private var trailerURL: URL?
    @State private var watchProviders: TMDBRegionProviders?
    @State private var providersLoaded = false
    @State private var confirmingRemoval = false

    private var titleID: String { "\(mediaType.rawValue)-\(tmdbID)" }
    private var title: Title? { appState.library.titles[titleID] }
    private var displayTitle: Title? { title ?? previewTitle }
    private var isTracked: Bool { appState.library.entries.contains { $0.id == titleID } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            hero
            if providersLoaded {
                WhereToWatchSection(providers: watchProviders, region: ConfigStore.defaultRegion)
            }
            if let title {
                if mediaType == .tv {
                    tvEpisodeList(for: title)
                } else {
                    movieReleaseList
                }
            } else if previewTitle == nil {
                SkeletonDetail()
            }
            if !cast.isEmpty {
                castSection
            }
        }
        .padding(.top, Theme.Space.xs)
        .task(id: titleID) {
            async let castFetch: [TMDBCastMember] = appState.fetchCredits(tmdbID: tmdbID, mediaType: mediaType)
            async let trailerFetch: URL? = appState.fetchTrailer(tmdbID: tmdbID, mediaType: mediaType)
            async let providersFetch: TMDBRegionProviders? = appState.fetchWatchProviders(
                mediaType: mediaType, tmdbID: tmdbID, region: ConfigStore.defaultRegion)
            if title != nil {
                await appState.refreshTitle(titleID)
            } else {
                previewTitle = await appState.fetchPreviewTitle(tmdbID: tmdbID, mediaType: mediaType)
            }
            trailerURL = await trailerFetch
            watchProviders = await providersFetch
            providersLoaded = true
            cast = await castFetch
        }
        .confirmationDialog(
            "Remove \(displayTitle?.name ?? name) from your library?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                appState.removeFromLibrary(titleID)
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Its episodes and watch history will be removed from this Mac.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            PosterImage(
                path: displayTitle?.posterPath,
                size: "w342",
                width: 160,
                height: 240,
                cornerRadius: Theme.Radius.m
            )

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(displayTitle?.name ?? name)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    metaChips
                }

                if let overview = displayTitle?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Theme.Space.s) {
                    watchlistButton
                    if let url = trailerURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Trailer", systemImage: "play.rectangle")
                        }
                        .buttonStyle(.bordered)
                        .help("Opens the trailer on YouTube")
                    }
                }

                if let callout = nextCallout {
                    calloutView(callout)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Space.l)
        .background(PosterTintedCard(posterPath: displayTitle?.posterPath, cornerRadius: Theme.Radius.l))
    }

    private var metaChips: some View {
        HStack(spacing: 6) {
            Chip(text: mediaType == .tv ? "Show" : "Movie")
            if let status = displayTitle?.tvStatus, !status.isEmpty {
                Chip(text: status)
            }
            if let year = yearText {
                Chip(text: year)
            }
        }
    }

    private var watchlistButton: some View {
        Group {
            if isTracked {
                Button {
                    confirmingRemoval = true
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    if let t = displayTitle {
                        appState.addToLibrary(t)
                        // Pull episodes and releases right after adding.
                        Task { await appState.refreshTitle(titleID) }
                    }
                } label: {
                    Label("Add to Watchlist", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentFill)
            }
        }
        .disabled(displayTitle == nil)
    }

    private func calloutView(_ callout: Callout) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "bell.badge")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(callout.title)
                    .font(.subheadline.weight(.semibold))
                Text(callout.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.accent.opacity(0.10))
        )
    }

    // MARK: - Episode selection

    @State private var isSelectingEpisodes = false
    @State private var selectedEpisodeIDs: Set<String> = []

    private var episodeHeader: some View {
        HStack(spacing: Theme.Space.m) {
            Text("Episodes")
                .font(.headline)
            Spacer(minLength: 0)
            Button(isSelectingEpisodes ? "Done" : "Select Episodes") {
                withAnimation(Motion.smooth) {
                    isSelectingEpisodes.toggle()
                    if !isSelectingEpisodes { selectedEpisodeIDs.removeAll() }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Pick several episodes and mark them watched at once")
        }
    }

    private func selectionBar(episodes: [Episode]) -> some View {
        let aired = episodes.filter { ($0.airDate ?? .distantFuture) <= .now }
        let hasSelection = !selectedEpisodeIDs.isEmpty
        return HStack(spacing: Theme.Space.m) {
            Text("\(selectedEpisodeIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Select all aired") {
                withAnimation(Motion.quick) { selectedEpisodeIDs.formUnion(aired.map(\.id)) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Mark Watched") { applySelection(watched: true) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasSelection)
            Button("Unmark") { applySelection(watched: false) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasSelection)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(Theme.chip)
        )
    }

    private func toggleSelected(_ episode: Episode) {
        if selectedEpisodeIDs.contains(episode.id) {
            selectedEpisodeIDs.remove(episode.id)
        } else {
            selectedEpisodeIDs.insert(episode.id)
        }
    }

    private func applySelection(watched: Bool) {
        let chosen = (appState.library.episodes[titleID] ?? [])
            .filter { selectedEpisodeIDs.contains($0.id) }
        appState.setEpisodesWatched(watched, episodes: chosen, titleID: titleID)
        withAnimation(Motion.smooth) {
            isSelectingEpisodes = false
            selectedEpisodeIDs.removeAll()
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private func tvEpisodeList(for title: Title) -> some View {
        // Only seasons TMDB actually announced: listed episodes, a premiere date, or the
        // "next episode to air" points at it. Dangling zero-episode records without either
        // would misrepresent an unannounced season as scheduled.
        let seasons = title.seasons.filter { season in
            guard season.seasonNumber > 0 else { return false }
            return season.episodeCount > 0
                || season.airDate != nil
                || season.seasonNumber == title.nextAiring?.seasonNumber
        }.map(\.seasonNumber).sorted(by: >)

        VStack(alignment: .leading, spacing: Theme.Space.s) {
            episodeHeader

            if seasons.isEmpty {
                Text("No seasons listed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Default to the newest season; the user can pick an earlier one freely.
                Menu {
                    ForEach(seasons, id: \.self) { season in
                        Button {
                            selectedSeason = season
                        } label: {
                            if season == (selectedSeason ?? seasons.first) {
                                Label("Season \(season)", systemImage: "checkmark")
                            } else {
                                Text("Season \(season)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Text("Season \(selectedSeason ?? seasons.first ?? 1)")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.xs)
                    .background(Theme.chip, in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose a season")

                let episodes = (appState.library.episodes[titleID] ?? [])
                    .filter { $0.seasonNumber == (selectedSeason ?? seasons.first) }
                    .sorted { $0.episodeNumber < $1.episodeNumber }

                if isSelectingEpisodes {
                    selectionBar(episodes: episodes)
                }

                if episodes.isEmpty {
                    seasonEmptyCard(for: title, season: selectedSeason ?? seasons.first ?? 0)
                }

                ForEach(episodes) { episode in
                    EpisodeRowView(
                        episode: episode,
                        isWatched: appState.library.isWatched(episode),
                        onToggleWatched: isSelectingEpisodes ? nil : {
                            withAnimation(Motion.smooth) {
                                appState.setEpisodeWatched(
                                    !appState.library.isWatched(episode),
                                    episode: episode,
                                    titleID: titleID
                                )
                            }
                        },
                        isSelected: selectedEpisodeIDs.contains(episode.id),
                        onToggleSelected: isSelectingEpisodes ? { withAnimation(Motion.quick) { toggleSelected(episode) } } : nil
                    )
                }
            }
        }
    }

    /// Graceful placeholder for a season TMDB has listed but that carries no episodes yet
    /// (typically an announced-but-not-scheduled season). Mentions the premiere when known.
    private func seasonEmptyCard(for title: Title, season: Int) -> some View {
        let airing = title.nextAiring
        let headline: String
        let detail: String
        if let date = airing?.airDate, airing?.seasonNumber == season {
            headline = "Season \(season) premieres \(DateText.upcoming(date))"
            detail = "Episodes will appear here as soon as they're listed."
        } else {
            headline = "No episodes listed yet"
            detail = "Season \(season) hasn't been announced. Check back after the next daily refresh."
        }
        return HStack(spacing: Theme.Space.m) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.chip)
        )
    }

    // MARK: - Movie releases

    private var movieReleaseList: some View {
        let releases = (appState.library.movieReleases[titleID] ?? [])
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                Text("Releases")
                    .font(.headline)
                Spacer(minLength: 0)
                movieWatchedButton
            }

            if releases.isEmpty {
                Text("No release dates listed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(releases) { release in
                        HStack {
                            Image(systemName: "film")
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(release.kind.label)
                                    .fontWeight(.medium)
                                Text(release.region)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(releaseDateLabel(release))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Theme.Space.s)
                        if release.id != releases.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(Theme.chip)
                )
            }
        }
    }

    /// Movies are watched as a whole, so the toggle sits on the section rather than a row.
    private var movieWatchedButton: some View {
        let watched = appState.library.isWatchedMovie(titleID)
        return Button {
            withAnimation(Motion.smooth) {
                appState.setMovieWatched(!watched, titleID: titleID)
            }
        } label: {
            Label(
                watched ? "Watched" : "Mark Watched",
                systemImage: watched ? "checkmark.circle.fill" : "circle"
            )
            .font(.caption)
            .foregroundStyle(watched ? Theme.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(watched ? "Mark as unwatched" : "Mark as watched")
    }

    // MARK: - Cast

    private var castSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Starring")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(cast.prefix(20), id: \.id) { member in
                        castCell(member)
                    }
                }
                .padding(.bottom, Theme.Space.xs)
            }
        }
    }

    /// One cast cell with the person popover attached. Kept as its own function so the
    /// compiler does not have to type-check the whole section at once.
    private func castCell(_ member: TMDBCastMember) -> some View {
        let isPresented = Binding(
            get: { selectedCastID == member.id },
            set: { if !$0 { selectedCastID = nil } }
        )
        return CastMemberView(member: member)
            .onTapGesture { selectedCastID = member.id }
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                PersonPopoverView(member: member, appState: appState)
            }
    }

    // MARK: - Helpers

    private var yearText: String? {
        guard let date = displayTitle?.firstAirDate else { return nil }
        return date.formatted(.dateTime.year())
    }

    private struct Callout {
        let title: String
        let detail: String
    }

    /// Next thing happening for this title, if any — drives the highlighted countdown callout.
    private var nextCallout: Callout? {
        if mediaType == .tv {
            guard let episode = appState.library.nextEpisode(forTitle: titleID),
                  let date = episode.airDate else { return nil }
            let hasTime = episode.airTimestamp != nil
            let when = DateText.upcoming(date, includeTime: hasTime)
            return Callout(
                title: "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name)",
                detail: "In \(DateText.relative(date)) · \(when)"
            )
        } else {
            guard let release = (appState.library.movieReleases[titleID] ?? [])
                .filter({ ($0.date ?? .distantPast) >= .now })
                .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }),
                  let date = release.date else { return nil }
            let when = DateText.upcoming(date, includeTime: release.hasTime)
            let suffix = release.hasTime ? "" : " (no time announced)"
            return Callout(
                title: "\(release.kind.label) release",
                detail: "In \(DateText.relative(date)) · \(when)\(suffix)"
            )
        }
    }

    private func releaseDateLabel(_ release: MovieRelease) -> String {
        guard let date = release.date else { return "TBD" }
        return DateText.upcoming(date, includeTime: release.hasTime)
    }
}


