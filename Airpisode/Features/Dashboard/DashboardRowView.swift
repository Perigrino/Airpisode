import SwiftUI

struct DashboardRowView: View {
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: 14) {
            // Hobi-style countdown rail badge: the relative time lives on the gradient chip.
            CountdownText(date: item.date)
                .frame(width: 62, height: 62)
                .background(Theme.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            PosterImage(path: item.title.posterPath, width: 52, height: 78, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: item.title.mediaType == .tv ? "tv" : "film")
                    Text(item.label)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text(dateLabel)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.cardBackground(cornerRadius: 16))
    }

    private var dateLabel: String {
        guard let date = item.date else { return "TBD" }
        let formatter = DateFormatter()
        formatter.dateFormat = item.isTimed ? "MMM d, HH:mm" : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
