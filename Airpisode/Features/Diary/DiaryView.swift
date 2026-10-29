import SwiftUI

/// A chronological record of what the user has marked watched, including movies. Legacy
/// watches without timestamps live in an “Earlier” bucket rather than getting a fake date.
struct DiaryView: View {
    @EnvironmentObject private var appState: AppState
    @SceneStorage("diary.search") private var searchText = ""
    @AppStorage("diary.filter") private var filterRaw = DiaryFilter.all.rawValue

    private var filter: DiaryFilter {
        DiaryFilter(rawValue: filterRaw) ?? .all
    }

    private var entries: [DiaryEntry] {
        appState.library.diaryEntries(filter: filter, search: searchText)
    }

    private var stats: DiaryStats { appState.library.diaryStats() }

    private var hasHistory: Bool {
        stats.lifetimeTotal > 0 || stats.undatedCount > 0
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != .all
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                if !hasHistory {
                    EmptyState(
                        systemImage: "clock.arrow.circlepath",
                        title: "Your diary is empty",
                        message: "Mark an episode or movie watched and it lands here with the date.",
                        actionTitle: "Go to To Watch"
                    ) {
                        appState.selectedSection = .dashboard
                    }
                } else {
                    statsCard

                    if entries.isEmpty {
                        if isFiltering {
                            EmptyState(
                                systemImage: "magnifyingglass",
                                title: "No matches",
                                message: "Try a different show, episode, or filter.",
                                actionTitle: "Clear search and filters"
                            ) {
                                clearFilters()
                            }
                        } else {
                            EmptyState(
                                systemImage: "clock",
                                title: "Nothing watched in the last 7 days",
                                message: "Your full history is still counted in the stats above."
                            )
                        }
                    } else {
                        ForEach(groups) { group in
                            groupView(group)
                        }
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search diary")
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Filter", selection: filterBinding) {
                ForEach(DiaryFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Filter diary entries")
        }
    }

    private var filterBinding: Binding<DiaryFilter> {
        Binding(
            get: { filter },
            set: { filterRaw = $0.rawValue }
        )
    }

    private func clearFilters() {
        searchText = ""
        filterRaw = DiaryFilter.all.rawValue
    }

    // MARK: - Summary

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: 0) {
                stat("This month", "\(stats.monthTotal)")
                statDivider
                stat("Episodes", "\(stats.lifetimeEpisodes)")
                statDivider
                stat("Movies", "\(stats.lifetimeMovies)")
                statDivider
                stat("Day streak", "\(stats.currentStreak)")
            }

            if stats.undatedCount > 0 {
                Text("\(stats.undatedCount) watch\(stats.undatedCount == 1 ? "" : "es") from before dates were recorded appear under Earlier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.cardBackground(cornerRadius: Theme.Radius.l))
        .accessibilityElement(children: .contain)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 32)
            .padding(.horizontal, Theme.Space.m)
    }

    // MARK: - Groups

    private func groupView(_ group: DiaryGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: group.title, count: group.entries.count)

            VStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    row(entry)
                    if entry.id != group.entries.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .padding(.horizontal, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground(cornerRadius: Theme.Radius.l))
        }
        .appear()
    }

    private func row(_ entry: DiaryEntry) -> some View {
        HStack(spacing: Theme.Space.m) {
            PosterImage(path: entry.title.posterPath, width: 40, height: 60, cornerRadius: Theme.Radius.s)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(entry.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Space.s)

            Text(timeText(entry.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                withAnimation(Motion.smooth) { undo(entry) }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark unwatched")
            .accessibilityLabel("Mark \(entry.title.name) unwatched")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func undo(_ entry: DiaryEntry) {
        if let episode = entry.episode {
            appState.setEpisodeWatched(false, episode: episode, titleID: entry.record.titleID)
        } else if entry.kind == .movie {
            appState.setMovieWatched(false, titleID: entry.record.titleID)
        }
    }

    // MARK: - Grouping

    private struct DiaryGroup: Identifiable {
        let id: String
        let title: String
        var entries: [DiaryEntry]
    }

    private var groups: [DiaryGroup] {
        var result: [DiaryGroup] = []
        for entry in entries {
            let key = groupKey(entry.date)
            if let index = result.firstIndex(where: { $0.id == key.id }) {
                result[index].entries.append(entry)
            } else {
                result.append(DiaryGroup(id: key.id, title: key.title, entries: [entry]))
            }
        }
        return result
    }

    private func groupKey(_ date: Date?) -> (id: String, title: String) {
        guard let date else { return ("earlier", "Earlier") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return ("today", "Today") }
        if calendar.isDateInYesterday(date) { return ("yesterday", "Yesterday") }
        let start = calendar.startOfDay(for: date)
        return (
            "day-\(Int(start.timeIntervalSince1970))",
            date.formatted(.dateTime.month(.wide).day().year())
        )
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "Watched earlier" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
