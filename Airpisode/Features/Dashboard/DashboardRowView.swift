import SwiftUI

struct DashboardRowView: View {
    let item: UpcomingItem

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: ImageURL.poster(item.title.posterPath)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.name)
                    .fontWeight(.medium)
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Date-only releases show the day only; timed ones show a clock time.
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.isTimed {
                    Text("No time announced")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var dateLabel: String {
        guard let date = item.date else { return "TBD" }
        let formatter = DateFormatter()
        if item.isTimed {
            formatter.dateFormat = "MMM d 'at' HH:mm"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}
