import SwiftUI

/// Hobi-inspired dark theme: near-black canvas, purple→magenta gradient accent.
enum Theme {
    static let accent = Color(red: 0.60, green: 0.42, blue: 0.95)   // purple
    static let accentMagenta = Color(red: 0.85, green: 0.35, blue: 0.85)
    static let background = Color(nsColor: .black)
    static let card = Color.white.opacity(0.05)
    static let chip = Color.white.opacity(0.08)

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

    /// Rounded card background used for inline detail panels and rows.
    static func cardBackground(cornerRadius: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(card)
    }

    /// Placeholder tint shown while a poster loads.
    static var posterPlaceholder: some View {
        Color.white.opacity(0.06)
    }
}

/// Page canvas: near-black background behind scroll content.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}


