import SwiftUI
import AppKit

/// App-wide design tokens.
///
/// One adaptive palette for light and dark, so the app follows the system instead of
/// forcing a theme. Content surfaces are flat; glass is reserved for the sidebar and
/// toolbar, which AppKit draws. See `docs/DESIGN.md` for the table.
enum Theme {
    // MARK: - Palette

    /// Page canvas behind scrolling content.
    static let background = dynamic(
        light: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1),
        dark: NSColor(srgbRed: 0.055, green: 0.055, blue: 0.067, alpha: 1)
    )

    /// Card surface — one step above the canvas.
    static let card = dynamic(
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.129, alpha: 1)
    )

    /// Low-emphasis fill for chips, fields, and countdown rails.
    static let chip = dynamic(
        light: NSColor(white: 0, alpha: 0.055),
        dark: NSColor(white: 1, alpha: 0.075)
    )

    /// 1 pt border around cards and fields.
    static let hairline = dynamic(
        light: NSColor(white: 0, alpha: 0.09),
        dark: NSColor(white: 1, alpha: 0.09)
    )

    /// Accent for text, symbols, and selection.
    static let accent = dynamic(
        light: NSColor(srgbRed: 0.357, green: 0.204, blue: 0.769, alpha: 1),
        dark: NSColor(srgbRed: 0.706, green: 0.612, blue: 1.0, alpha: 1)
    )

    /// Accent for filled controls. Deep enough for white text in both appearances.
    static let accentFill = dynamic(
        light: NSColor(srgbRed: 0.427, green: 0.247, blue: 0.820, alpha: 1),
        dark: NSColor(srgbRed: 0.486, green: 0.361, blue: 0.878, alpha: 1)
    )

    static let accentSecondary = dynamic(
        light: NSColor(srgbRed: 0.784, green: 0.271, blue: 0.722, alpha: 1),
        dark: NSColor(srgbRed: 0.914, green: 0.478, blue: 0.843, alpha: 1)
    )

    static let onAccent = Color.white

    /// Brand gradient: the app mark and nothing else.
    static let gradient = LinearGradient(
        colors: [accentFill, accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Metrics

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    // MARK: - Surfaces

    /// Page canvas: the adaptive background with two barely-there accent glows so a
    /// large window does not read as a flat void. Works in both appearances.
    static var canvas: some View {
        ZStack {
            background
            RadialGradient(
                colors: [accent.opacity(0.055), .clear],
                center: UnitPoint(x: 0.08, y: -0.10), startRadius: 0, endRadius: 620
            )
            RadialGradient(
                colors: [accentSecondary.opacity(0.04), .clear],
                center: UnitPoint(x: 1.05, y: 1.10), startRadius: 0, endRadius: 700
            )
        }
    }

    /// Flat card surface with a hairline. No glass: content is not chrome.
    static func cardBackground(cornerRadius: CGFloat = Radius.l) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 1)
            )
    }

    static var posterPlaceholder: some View {
        chip
    }

    // MARK: - Helpers

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Page canvas: adaptive background behind scroll content.
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
