import SwiftUI

/// Something shown in the History list: a released-but-unwatched episode or movie.
protocol HistoryItem: Identifiable {
    var title: Title { get }
    var date: Date? { get }
    var label: String { get }
}

extension ReleasedEpisode: HistoryItem {}
extension ReleasedMovie: HistoryItem {}

/// "Released · not watched yet" — rows stay here until they're marked watched, then they're gone.
///
/// Shared by My Shows (episodes) and My Movies (movies). Hides itself when empty.
struct HistorySection<Item: HistoryItem>: View {
    let items: [Item]
    var heading = "Aired"
    let onMarkWatched: (Item) -> Void

    private enum Bucket: String, CaseIterable, Identifiable {
        case today = "Today"
        case thisWeek = "This Week"
        case earlier = "Earlier"

        var id: String { rawValue }
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(Bucket.allCases) { bucket in
                    let bucketItems = items.filter { self.bucket(for: $0) == bucket }
                    if !bucketItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(bucket.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(bucketItems) { item in
                                row(item)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PosterTintedCard(posterPath: nil))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(heading)
                .font(.title3)
                .fontWeight(.semibold)
            Text("Released · not watched yet")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            PosterImage(path: item.title.posterPath, width: 40, height: 60, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(dateText(item.date))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                withAnimation(Motion.smooth) { onMarkWatched(item) }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help("Mark as watched")
        }
        .padding(.vertical, 2)
        .hoverLift()
    }

    private func bucket(for item: Item) -> Bucket {
        guard let date = item.date else { return .earlier }
        let today = Calendar.current.startOfDay(for: .now)
        if date >= today { return .today }
        if date >= today.addingTimeInterval(-6 * 86_400) { return .thisWeek }
        return .earlier
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "TBD" }
        return EpisodeRowView.dayFormatter.string(from: date)
    }
}
