import SwiftUI

/// Poster/photo thumbnail that fades in once it finishes loading.
struct PosterImage: View {
    let path: String?
    var size: String = "w185"
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded = false

    var body: some View {
        AsyncImage(url: ImageURL.poster(path, size: size)) { phase in
            if let image = phase.image {
                image.resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(loaded ? 1 : 0)
                    .onAppear {
                        if reduceMotion {
                            loaded = true
                        } else {
                            withAnimation(.easeOut(duration: 0.28)) { loaded = true }
                        }
                    }
            } else {
                Theme.posterPlaceholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
