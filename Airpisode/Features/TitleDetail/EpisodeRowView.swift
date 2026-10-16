import SwiftUI

struct EpisodeRowView: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
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
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
