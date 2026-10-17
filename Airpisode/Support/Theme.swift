import SwiftUI

/// Hobi-inspired dark theme: near-black canvas, purple→magenta gradient accent.
enum Theme {
    static let accent = Color(red: 0.60, green: 0.42, blue: 0.95)   // purple
    static let accentMagenta = Color(red: 0.85, green: 0.35, blue: 0.85)
    static let background = Color(nsColor: .black)
    static let card = Color.white.opacity(0.05)
    static let chip = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.08)

    static let gradient = LinearGradient(
        colors: [accent, accentMagenta],
        startPoint: .top,
        endPoint: .bottom
    )

    static let horizontalGradient = LinearGradient(
        colors: [accent, accentMagenta],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Page canvas: near-black with soft accent glows in two corners so the screen
    /// reads as depth rather than a flat void. Content scrolls over it.
    static var canvas: some View {
        ZStack {
            background
            RadialGradient(
                colors: [accent.opacity(0.22), .clear],
                center: UnitPoint(x: 0.10, y: -0.06), startRadius: 0, endRadius: 640
            )
            RadialGradient(
                colors: [accentMagenta.opacity(0.16), .clear],
                center: UnitPoint(x: 1.08, y: 1.12), startRadius: 0, endRadius: 720
            )
        }
    }

    /// Translucent card surface with a soft top highlight — a material catching light.
    static func cardBackground(cornerRadius: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.14), .white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }

    /// Placeholder tint shown while a poster loads.
    static var posterPlaceholder: some View {
        Color.white.opacity(0.06)
    }
}

/// Page canvas: gradient background behind scroll content.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
