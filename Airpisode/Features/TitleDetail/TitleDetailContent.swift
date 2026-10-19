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

    private var titleID: String { "\(mediaType.rawValue)-\(tmdbID)" }
    private var title: Title? { appState.library.titles[titleID] }
    private var displayTitle: Title? { title ?? previewTitle }
    private var isTracked: Bool { appState.library.entries.contains { $0.id == titleID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
        .padding(.top, 4)
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
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            PosterImage(path: displayTitle?.posterPath, size: "w342", width: 200, height: 300, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 12) {
                Text(displayTitle?.name ?? name)
                    .font(.title).bold()

                metaChips

                if let overview = displayTitle?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }

                HStack(spacing: 8) {
                    watchlistButton
                    if let url = trailerURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Trailer", systemImage: "play.rectangle.on.rectangle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Opens the trailer on YouTube")
                    }
                }

                if let callout = nextCallout {
                    calloutView(callout)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(heroBackdrop)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Blurred poster wash behind the hero — a translucent panel, Hobi-style.
    private var heroBackdrop: some View {
        ZStack {
            Theme.accent.opacity(0.10)
            if let path = displayTitle?.posterPath, let url = ImageURL.poster(path, size: "w342") {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill).blur(radius: 50)
                } placeholder: {
                    Color.clear
                }
                .opacity(0.4)
            }
            LinearGradient(
                colors: [.black.opacity(0.10), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var metaChips: some View {
        HStack(spacing: 6) {
            Chip(text: mediaType == .tv ? "TV Show" : "Movie")
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
                Button(role: .destructive) {
                    appState.removeFromLibrary(titleID)
                } label: {
                    Label("Remove from Watchlist", systemImage: "minus.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.regular)
            } else {
                Button {
                    if let t = displayTitle {
                        appState.addToLibrary(t)
                        Task { await appState.refreshTitle(titleID) }  // pull episodes/releases right after adding
                    }
                } label: {
                    Label("Add to Watchlist", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.regular)
            }
        }
        .disabled(displayTitle == nil)
    }

    private func calloutView(_ callout: Callout) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(callout.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(callout.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.15)))
    }

    // MARK: - Episode selection

    @State private var isSelectingEpisodes = false
    @State private var selectedEpisodeIDs: Set<String> = []

    /// Header for the episode list, with the bulk-selection switch.
    private var episodeHeader: some View {
        HStack(spacing: 12) {
            Text("Episodes").font(.headline)
            Spacer(minLength: 0)
            Button(isSelectingEpisodes ? "Done" : "Select") {
                withAnimation(Motion.smooth) {
                    isSelectingEpisodes.toggle()
                    if !isSelectingEpisodes { selectedEpisodeIDs.removeAll() }
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Theme.accent)
            .help("Pick several episodes and mark them watched at once")
        }
    }

    /// Shown while selecting: a count plus the bulk actions.
    private func selectionBar(episodes: [Episode]) -> some View {
        let aired = episodes.filter { ($0.airDate ?? .distantFuture) <= .now }
        let hasSelection = !selectedEpisodeIDs.isEmpty
        return HStack(spacing: 14) {
            Text("\(selectedEpisodeIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Select all aired") {
                withAnimation(Motion.quick) { selectedEpisodeIDs.formUnion(aired.map(\.id)) }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Theme.accent)
            Button("Mark watched") { applySelection(watched: true) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(hasSelection ? Theme.accent : Color.secondary)
                .disabled(!hasSelection)
            Button("Unmark") { applySelection(watched: false) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(hasSelection ? Theme.accent : Color.secondary)
                .disabled(!hasSelection)
        }
    }

    private func toggleSelected(_ episode: Episode) {
        if selectedEpisodeIDs.contains(episode.id) {
            selectedEpisodeIDs.remove(episode.id)
        } else {
            selectedEpisodeIDs.insert(episode.id)
        }
    }

    /// Applies the picked episodes across every season, then leaves selection mode.
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
        }.map(\.seasonNumber).sorted()
        if seasons.isEmpty {
            Text("No seasons listed").foregroundStyle(.secondary)
        } else {
            episodeHeader

            // Default to the newest season; the user can pick an earlier one freely.
            Picker("Season", selection: Binding(
                get: { selectedSeason ?? seasons.last },
                set: { selectedSeason = $0 }
            )) {
                ForEach(seasons, id: \.self) { season in
                    Text("Season \(season)").tag(season)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            let episodes = (appState.library.episodes[titleID] ?? [])
                .filter { $0.seasonNumber == (selectedSeason ?? seasons.last) }
                .sorted { $0.episodeNumber < $1.episodeNumber }

            if isSelectingEpisodes {
                selectionBar(episodes: episodes)
            }

            if episodes.isEmpty {
                seasonEmptyCard(
                    for: title,
                    season: selectedSeason ?? seasons.last ?? 0
                )
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

    /// Graceful placeholder for a season TMDB has listed but that carries no episodes yet
    /// (typically an announced-but-not-scheduled season). Mentions the premiere when known.
    private func seasonEmptyCard(for title: Title, season: Int) -> some View {
        let airing = title.nextAiring
        let headline: String
        let detail: String
        if let date = airing?.airDate, airing?.seasonNumber == season {
            headline = "Season \(season) premieres \(date.formatted(date: .abbreviated, time: .omitted))"
            detail = "Episodes will appear here as soon as they're listed."
        } else {
            headline = "No episodes listed yet"
            detail = "Season \(season) hasn't been announced. Check back after the next daily refresh."
        }
        return HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.callout).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.chip))
    }

    // MARK: - Movie releases

    private var movieReleaseList: some View {
        let releases = (appState.library.movieReleases[titleID] ?? [])
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return Group {
            if releases.isEmpty {
                Text("No release dates listed").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    Text("Releases").font(.headline)
                    Spacer(minLength: 0)
                    movieWatchedButton
                }
                ForEach(releases) { release in
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(release.kind.label).fontWeight(.medium)
                            Text(release.region).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(releaseDateLabel(release))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
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
            Label(watched ? "Watched" : "Mark watched",
                  systemImage: watched ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(watched ? Theme.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(watched ? "Mark as unwatched" : "Mark as watched")
    }

    // MARK: - Cast

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Starring")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(cast.prefix(20), id: \.id) { member in
                        castCell(member)
                    }
                }
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
            .hoverLift()
            .onTapGesture { selectedCastID = member.id }
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                PersonPopoverView(member: member, appState: appState)
            }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yearText: String? {
        guard let date = displayTitle?.firstAirDate else { return nil }
        return Self.yearFormatter.string(from: date)
    }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    private struct Callout {
        let title: String
        let detail: String
    }

    /// Next thing happening for this title, if any — drives the highlighted countdown callout.
    private var nextCallout: Callout? {
        if mediaType == .tv {
            guard let episode = appState.library.nextEpisode(forTitle: titleID) else { return nil }
            let detail = episode.airDate.map { "\(Self.relativeLabel($0)) · \(EpisodeRowView.dayFormatter.string(from: $0))" } ?? "Air date TBD"
            return Callout(title: "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.name)", detail: detail)
        } else {
            guard let release = (appState.library.movieReleases[titleID] ?? [])
                .filter({ ($0.date ?? .distantPast) >= .now })
                .min(by: { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }),
                  let date = release.date else { return nil }
            // Only promise a time when the source actually has one.
            let detail = release.hasTime
                ? "\(Self.relativeLabel(date)) · \(releaseDateLabel(release))"
                : "\(Self.relativeLabel(date)) · \(releaseDateLabel(release)) (no time announced)"
            return Callout(title: "\(release.kind.label) release", detail: detail)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func relativeLabel(_ date: Date) -> String {
        let now = Date.now
        if date <= now { return "Out now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    private func releaseDateLabel(_ release: MovieRelease) -> String {
        guard let date = release.date else { return "TBD" }
        let formatter = DateFormatter()
        if release.hasTime {
            formatter.dateFormat = "MMM d, yyyy 'at' HH:mm"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }
}

extension ReleaseKind {
    var label: String {
        switch self {
        case .theatrical: return "Theatrical"
        case .digital: return "Digital"
        case .physical: return "Physical"
        case .tv: return "TV"
        }
    }
}
