import SwiftUI

/// App-wide motion personality — a single "Silk" seed: smooth, fluid, critically damped.
/// One personality for the whole product (see the ss-motion skill: one seed per product).
/// Critically damped (dampingFraction 1.0) means no overshoot — that tiny bounce is what
/// reads as "jitter", so removing it is what makes the motion feel smoother.
enum Motion {
    /// Default for user-driven layout changes (expand, filter, insert).
    static let smooth = Animation.spring(response: 0.45, dampingFraction: 1.0)
    /// Immediate feedback (hover, press).
    static let quick = Animation.spring(response: 0.28, dampingFraction: 1.0)
    /// Large, deliberate moves that should settle unhurriedly (page-level reveals).
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 1.0)
}

/// Gentle fade-up for transient/empty/error states — never for primary payload content.
private struct AppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.gentle) { shown = true }
            }
    }
}

/// Subtle hover lift for clickable cards/rows (desktop affordance).
private struct HoverLiftModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.006 : 1)
            .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 14, y: 6)
            .animation(Motion.smooth, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Fade + rise on first appearance (transient states, not payload rows).
    func appear() -> some View { modifier(AppearModifier()) }

    /// Gentle scale + shadow on hover for clickable cards.
    func hoverLift() -> some View { modifier(HoverLiftModifier()) }
}
