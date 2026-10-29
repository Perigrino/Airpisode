import SwiftUI

/// Plain row content (no background/padding of its own) — the hosting card supplies those.
struct TitleRowView: View {
    let title: Title
    let nextLabel: String?
    var isExpanded = false
    /// Small state badge (e.g. "Muted") rendered under the title.
    var badge: String? = nil
    var badgeIcon = "bell.slash"

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            PosterImage(path: title.posterPath, width: 44, height: 64, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(2)

                if let badge {
                    Label(badge, systemImage: badgeIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let nextLabel {
                    Text(nextLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(title.mediaType == .tv ? "No upcoming episode" : "No upcoming release")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Space.s)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(Motion.quick, value: isExpanded)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")
    }
}
