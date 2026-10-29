import SwiftUI

/// Page header: one title, one line of orientation. Used inside content, never as a
/// second window title.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section heading with an optional count and trailing accessory.
struct SectionHeader: View {
    let title: String
    var count: Int?
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(title)
                .font(.headline)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.chip, in: Capsule())
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rounded pill chip for media type and small state.
struct Chip: View {
    let text: String
    var systemImage: String?
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(filled ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.chip))
        )
        .foregroundStyle(filled ? Theme.onAccent : Color.secondary)
    }
}

/// Countdown rail: number over unit, tinted with the accent instead of a gradient block.
struct CountdownBadge: View {
    let date: Date?
    var now: Date = .now

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.3)
        }
        .foregroundStyle(Theme.accent)
        .frame(width: 54, height: 54)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.accent.opacity(0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var parts: (Int, String)? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        if seconds < 0 { return nil }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if minutes < 60 { return (max(minutes, 1), "min") }
        if hours < 24 { return (hours, "hr") }
        if days < 7 { return (days, "day") }
        if days < 30 { return (days / 7, "wk") }
        if days < 365 { return (days / 30, "mo") }
        return (days / 365, "yr")
    }

    private var value: String {
        if date == nil { return "—" }
        guard let parts else { return "Now" }
        return "\(parts.0)"
    }

    private var unit: String {
        guard let parts else { return date == nil ? "TBD" : "now" }
        return parts.0 == 1 ? parts.1 : parts.1 + "s"
    }

    private var accessibilityLabel: String {
        guard let date else { return "Release date to be announced" }
        if date <= now { return "Available now" }
        return "In " + DateText.relative(date, now: now)
    }
}

/// Filter pill: same surface as Chip, filled when selected, >= 22 pt tall.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.chip))
                )
                .foregroundStyle(isSelected ? Theme.onAccent : Color.secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Empty state that always offers the first useful action.
struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .appear()
    }
}

/// Inline, non-blocking problem banner with an optional recovery action.
struct InlineBanner: View {
    enum Tone { case warning, error, info }

    let message: String
    var tone: Tone = .warning
    var actionTitle: String?
    var action: (() -> Void)?

    private var symbol: String {
        switch tone {
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var color: Color {
        switch tone {
        case .warning: return .orange
        case .error: return .red
        case .info: return Theme.accent
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The in-app app mark: the "8b fade" icon — a play node over a rail that dissolves downward.
struct AppLogo: View {
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Theme.background)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Theme.accentFill.opacity(0.95), Theme.accentSecondary.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size * 0.066, height: size * 0.40)
                .offset(y: size * 0.057)

            Circle()
                .fill(.white)
                .frame(width: size * 0.27, height: size * 0.27)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: size * 0.12, weight: .bold))
                        .foregroundStyle(Theme.gradient)
                )
                .offset(y: -size * 0.145)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.28), radius: size * 0.16, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

/// Small portrait for cast rows.
struct CastAvatar: View {
    let name: String
    let profilePath: String?

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            AsyncImage(url: ImageURL.poster(profilePath, size: "w185")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Theme.chip
            }
            .frame(width: 64, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))

            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
