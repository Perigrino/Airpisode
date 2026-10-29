import SwiftUI

struct DashboardRowView: View {
    @EnvironmentObject private var appState: AppState
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            CountdownBadge(date: item.date)

            PosterImage(path: item.title.posterPath, width: 38, height: 56, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.cardBackground(cornerRadius: Theme.Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        .contextMenu {
            Button(item.title.mediaType == .tv ? "Show in Shows" : "Show in Movies") {
                appState.selectedSection = item.title.mediaType == .tv ? .shows : .movies
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title.name), \(item.label), \(dateLabel)")
    }

    private var dateLabel: String {
        guard let date = item.date else { return "Date to be announced" }
        if item.isTimed {
            return DateText.upcoming(date, includeTime: true)
        }
        return DateText.upcoming(date)
    }
}
