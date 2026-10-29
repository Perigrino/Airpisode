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
/// Shared by To Watch, and reusable by any list of aired items. Hides itself when empty.
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
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(heading)
                        .font(.headline)
                    Text("\(items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("Aired · not watched")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(Bucket.allCases) { bucket in
                        let bucketItems = items.filter { self.bucket(for: $0) == bucket }
                        if !bucketItems.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bucket.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.bottom, 2)
                                ForEach(bucketItems) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground())
            .accessibilityElement(children: .contain)
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: Theme.Space.m) {
            PosterImage(path: item.title.posterPath, width: 34, height: 50, cornerRadius: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Text(dateText(item.date))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Mark watched") {
                withAnimation(Motion.smooth) { onMarkWatched(item) }
            }
            .controlSize(.small)
            .help("Mark \(item.title.name) as watched")
            .accessibilityLabel("Mark \(item.title.name) as watched")
        }
        .padding(.vertical, 3)
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
        return DateText.airing(date)
    }
}
