import SwiftUI

/// Sweeping sheen for loading placeholders — the "shimmer" shown while content loads.
private struct ShimmerModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.22), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.7)
                        .offset(x: phase * geo.size.width * 1.7)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Adds a repeating sheen. Use on loading placeholders only.
    func shimmer(cornerRadius: CGFloat = 8) -> some View {
        modifier(ShimmerModifier(cornerRadius: cornerRadius))
    }
}

/// A single shimmering placeholder block, sized like the content it stands in for.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    let height: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.chip)
            .frame(width: width, height: height)
            .shimmer(cornerRadius: cornerRadius)
    }
}

/// Placeholder row shaped like a Discover result: poster plus two text lines.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            SkeletonBlock(width: 60, height: 90, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 200, height: 16)
                SkeletonBlock(width: 120, height: 12)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.cardBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Placeholder hero shaped like the inline detail: poster plus title/meta/overview lines.
struct SkeletonDetail: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            SkeletonBlock(width: 200, height: 300, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 240, height: 26)
                HStack(spacing: 6) {
                    SkeletonBlock(width: 64, height: 22, cornerRadius: 11)
                    SkeletonBlock(width: 48, height: 22, cornerRadius: 11)
                }
                SkeletonBlock(height: 14)
                SkeletonBlock(width: 320, height: 14)
                SkeletonBlock(width: 280, height: 14)
                SkeletonBlock(width: 150, height: 30, cornerRadius: 8)
                Spacer(minLength: 0)
            }
        }
    }
}
