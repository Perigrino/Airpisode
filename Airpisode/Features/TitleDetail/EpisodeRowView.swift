import SwiftUI

struct EpisodeRowView: View {
    let episode: Episode

    private var aired: Bool {
        guard let date = episode.airDate else { return false }
        return date <= .now
    }

    var body: some View {
        HStack(spacing: 12) {
            // Hobi tracker dot: filled = aired, hollow = upcoming.
            Circle()
                .fill(aired ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear))
                .overlay(Circle().strokeBorder(Theme.accent.opacity(aired ? 0 : 0.7), lineWidth: 1.5))
                .frame(width: 10, height: 10)

            Text("S\(episode.seasonNumber)E\(episode.episodeNumber)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.name)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            // Date-only air dates render as a plain day; never invent a clock time.
            Text(episode.airDate.map { Self.dayFormatter.string(from: $0) } ?? "TBD")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
