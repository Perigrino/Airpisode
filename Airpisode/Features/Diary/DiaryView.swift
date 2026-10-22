import SwiftUI

/// A chronological record of what the user has marked watched, including movies. Legacy
/// watches without timestamps live in an “Earlier” bucket rather than getting a fake date.
struct DiaryView: View {
    @EnvironmentObject private var appState: AppState

    private var entries: [DiaryEntry] { appState.library.diaryEntries() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Diary",
                    subtitle: "Everything you've marked watched, newest first"
                )

                if entries.isEmpty {
                    emptyState
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
            .padding(24)
            .padding(.bottom, DockBar.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("Diary")
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
