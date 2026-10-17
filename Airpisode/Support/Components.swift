import SwiftUI

/// Hobi-style large page header: bold title with a lighter subtitle beneath.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rounded pill chip, optionally filled with the accent gradient (Hobi filter chips).
struct Chip: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(filled ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.chip))
            )
            .foregroundStyle(filled ? .white : .secondary)
    }
}

/// Relative countdown (e.g. "7 Hours", "3 Days", "2 Weeks", "1 Month") — Hobi rail label.
struct CountdownText: View {
    let date: Date?

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
    }

    private var label: String {
        guard let date else { return "TBD" }
        let seconds = date.timeIntervalSinceNow
        if seconds < 0 { return "Now" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if minutes < 60 {
            let m = max(minutes, 1)
            return "\(m)\n\(m == 1 ? "Min" : "Mins")"
        }
        if hours < 24 { return "\(hours)\n\(hours == 1 ? "Hour" : "Hours")" }
        if days < 7 { return "\(days)\n\(days == 1 ? "Day" : "Days")" }
        if days < 30 {
            let w = days / 7
            return "\(w)\n\(w == 1 ? "Week" : "Weeks")"
        }
        if days < 365 {
            let mo = days / 30
            return "\(mo)\n\(mo == 1 ? "Month" : "Months")"
        }
        let y = days / 365
        return "\(y)\n\(y == 1 ? "Year" : "Years")"
    }
}

/// Small circular avatar photo for cast (Hobi "Starring" row).
struct CastAvatar: View {
    let name: String
    let profilePath: String?

    var body: some View {
        VStack(spacing: 4) {
            AsyncImage(url: ImageURL.poster(profilePath, size: "w185")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 72, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }
}
