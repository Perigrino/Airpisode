import SwiftUI

/// A chronological record of what the user has marked watched, including movies. Legacy
/// watches without timestamps live in an “Earlier” bucket rather than getting a fake date.
struct DiaryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var filter: DiaryFilter = .all

    private var allEntries: [DiaryEntry] { appState.library.diaryEntries() }
    private var entries: [DiaryEntry] {
        appState.library.diaryEntries(filter: filter, search: searchText)
    }
    private var stats: DiaryStats { appState.library.diaryStats() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Diary",
                    subtitle: "Everything you've marked watched, newest first"
                )

                if allEntries.isEmpty {
                    emptyState
                } else {
                    statsCard
                    controls

                    if entries.isEmpty {
                        noMatches
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(group.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    Spacer()
                                    Text("\(group.entries.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                LazyVStack(spacing: 2) {
                                    ForEach(group.entries) { entry in
                                        row(entry)
                                        if entry.id != group.entries.last?.id {
                                            Divider().padding(.leading, 52)
                                        }
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PosterTintedCard(posterPath: nil))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .appear()
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
        .navigationTitle("Diary")
    }

    // MARK: - Summary

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .background(PosterTintedCard(posterPath: nil))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 30)
            .padding(.horizontal, 10)
    }

    // MARK: - Search and filter

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search diary", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            Picker("Filter", selection: $filter) {
                ForEach(DiaryFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.headline)
            Text("Try a different show, episode, or filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Clear filters") {
                withAnimation(Motion.smooth) {
                    searchText = ""
                    filter = .all
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Your diary is empty")
                .font(.headline)
            Text("Mark an episode or movie watched and it lands here with the date.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                appState.selectedSection = .dashboard
            } label: {
                Label("Go to To Watch", systemImage: "checklist")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Rows

    private func row(_ entry: DiaryEntry) -> some View {
        HStack(spacing: 12) {
            PosterImage(path: entry.title.posterPath, width: 40, height: 60, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(entry.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(timeText(entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                withAnimation(Motion.smooth) { undo(entry) }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Mark unwatched")
        }
        .padding(.vertical, 3)
        .hoverLift()
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
