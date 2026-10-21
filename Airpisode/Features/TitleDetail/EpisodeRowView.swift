import SwiftUI

struct EpisodeRowView: View {
    let episode: Episode
    /// Whether the user has already watched this episode. Ignored when `onToggleWatched` is nil.
    var isWatched: Bool = false
    /// When set, a watched toggle appears for episodes that have already aired.
    var onToggleWatched: (() -> Void)? = nil
    /// Whether this row is picked in bulk-selection mode.
    var isSelected: Bool = false
    /// When set, the row shows a selection checkbox instead of the watched toggle.
    var onToggleSelected: (() -> Void)? = nil

    private var airMoment: Date? {
        episode.airTimestamp ?? episode.airDate
    }

    private var aired: Bool {
        guard let date = airMoment else { return false }
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
            // Past episodes include the year, so they're unambiguous in a long list.
            Text(dateText)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Only aired episodes can have been watched, so the toggle appears only then.
            if aired {
                if let onToggleSelected {
                    Button(action: onToggleSelected) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isSelected ? "Deselect" : "Select")
                } else if let onToggleWatched {
                    Button(action: onToggleWatched) {
                        Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isWatched ? Theme.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isWatched ? "Mark as unwatched" : "Mark as watched")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        guard let date = airMoment else { return "TBD" }
        // Show the clock time only when it is actually known; a date-only release
        // intentionally renders as a plain day.
        if !aired, episode.airTimestamp != nil {
            return Self.upcomingFormatter.string(from: date)
        }
        let formatter = aired ? Self.fullDayFormatter : Self.dayFormatter
        return formatter.string(from: date)
    }

    static let upcomingFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
