import SwiftUI

/// App-wide motion personality — a single "Silk" seed: smooth, fluid, critically damped.
/// One personality for the whole product (see the ss-motion skill: one seed per product).
enum Motion {
    /// Default for user-driven layout changes (expand, filter, insert).
    static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.9)
    /// Immediate feedback (hover, press).
    static let quick = Animation.spring(response: 0.22, dampingFraction: 1.0)
}

/// Gentle fade-up for transient/empty/error states — never for primary payload content.
private struct AppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.smooth) { shown = true }
            }
    }
}

/// Subtle hover lift for clickable cards/rows (desktop affordance).
private struct HoverLiftModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.008 : 1)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Fade + rise on first appearance (transient states, not payload rows).
    func appear() -> some View { modifier(AppearModifier()) }

    /// Gentle scale on hover for clickable cards.
    func hoverLift() -> some View { modifier(HoverLiftModifier()) }
}
