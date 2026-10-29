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
        HStack(spacing: Theme.Space.m) {
            // Filled = aired, hollow = upcoming.
            Circle()
                .fill(aired ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear))
                .overlay(Circle().strokeBorder(Theme.accent.opacity(aired ? 0 : 0.7), lineWidth: 1.5))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text("S\(episode.seasonNumber)E\(episode.episodeNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.name)
                    .font(.subheadline)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Theme.Space.s)

            // Date-only air dates render as a plain day; never invent a clock time.
            Text(dateText)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Only aired episodes can have been watched, so the toggle appears only then.
            if aired {
                if let onToggleSelected {
                    toggleButton(
                        systemImage: isSelected ? "checkmark.circle.fill" : "circle",
                        help: isSelected ? "Deselect" : "Select",
                        action: onToggleSelected
                    )
                } else if let onToggleWatched {
                    toggleButton(
                        systemImage: isWatched ? "checkmark.circle.fill" : "circle",
                        help: isWatched ? "Mark as unwatched" : "Mark as watched",
                        action: onToggleWatched
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func toggleButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isWatched || isSelected ? Theme.accent : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var dateText: String {
        guard let date = airMoment else { return "TBD" }
        if aired {
            return DateText.airing(date)
        }
        return DateText.upcoming(date, includeTime: episode.airTimestamp != nil)
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
}
