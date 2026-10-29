import Foundation

/// Human date wording shared by every list so a row never shows a raw timestamp.
enum DateText {
    /// "3 hours", "2 days", "1 week" — a duration without a preposition.
    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        let magnitude = abs(seconds)
        if magnitude < 60 { return "less than a minute" }
        let minutes = Int(magnitude / 60)
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        let months = days / 30
        let years = days / 365
        let (value, unit): (Int, String)
        if minutes < 60 { (value, unit) = (minutes, "minute") }
        else if hours < 24 { (value, unit) = (hours, "hour") }
        else if days < 7 { (value, unit) = (days, "day") }
        else if days < 30 { (value, unit) = (weeks, "week") }
        else if days < 365 { (value, unit) = (months, "month") }
        else { (value, unit) = (years, "year") }
        return "\(value) \(unit)\(value == 1 ? "" : "s")"
    }

    /// Compact countdown: "2h", "3d", "1w", "2mo".
    static func compact(_ date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 0 { return "Now" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if minutes < 60 { return "\(max(minutes, 1))m" }
        if hours < 24 { return "\(hours)h" }
        if days < 7 { return "\(days)d" }
        if days < 30 { return "\(days / 7)w" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)y"
    }

    /// When something airs or releases: "Today, 2:00 AM", "Tomorrow", "Fri, Nov 1".
    static func upcoming(_ date: Date, now: Date = .now, calendar: Calendar = .current, includeTime: Bool = false) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case ..<0:
            return airing(date, now: now, calendar: calendar)
        case 0:
            return includeTime ? "Today, " + time(date) : "Today"
        case 1:
            return includeTime ? "Tomorrow, " + time(date) : "Tomorrow"
        case 2...6:
            let weekday = date.formatted(.dateTime.weekday(.abbreviated))
            return includeTime ? "\(weekday), " + time(date) : weekday
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let format: Date.FormatStyle = sameYear
                ? .dateTime.month(.abbreviated).day()
                : .dateTime.month(.abbreviated).day().year()
            return date.formatted(format) + (includeTime ? ", " + time(date) : "")
        }
    }

    /// When something already happened: "Today", "Yesterday", "3 days ago", "Oct 12".
    static func airing(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let format: Date.FormatStyle = sameYear
                ? .dateTime.month(.abbreviated).day()
                : .dateTime.month(.abbreviated).day().year()
            return date.formatted(format)
        }
    }

    /// Freshness of the last successful refresh.
    static func freshness(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Not refreshed yet" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Updated just now" }
        if seconds < 3600 { return "Updated \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "Updated \(Int(seconds / 3600)) hr ago" }
        return "Updated " + airing(date, now: now)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
