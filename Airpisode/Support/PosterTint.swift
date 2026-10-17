import SwiftUI
import AppKit

/// Samples a soft accent colour from a poster so list cards can carry a hint of the artwork.
/// Sampling runs off the main actor and results are cached per URL.
actor PosterColorCache {
    static let shared = PosterColorCache()

    private var cache: [String: Color] = [:]
    private var inFlight: [String: Task<Color?, Never>] = [:]

    func color(for path: String?, size: String = "w185") async -> Color? {
        guard let path, let url = ImageURL.poster(path, size: size) else { return nil }
        let key = url.absoluteString
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<Color?, Never> { await Self.sample(url) }
        inFlight[key] = task
        let color = await task.value
        inFlight[key] = nil
        if let color { cache[key] = color }
        return color
    }

    /// Average the poster's mid-tones, then lift saturation so the tint reads as intentional.
    private static func sample(_ url: URL) async -> Color? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let w = 16, h = 16
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { return nil }

        let buffer = raw.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * ctx.bytesPerRow + x * 4
                guard Double(buffer[i + 3]) / 255 > 0.1 else { continue }
                let pr = Double(buffer[i]) / 255
                let pg = Double(buffer[i + 1]) / 255
                let pb = Double(buffer[i + 2]) / 255
                let lum = 0.299 * pr + 0.587 * pg + 0.114 * pb
                // Skip letterboxing and title text so they don't muddy the average.
                if lum < 0.10 || lum > 0.94 { continue }
                r += pr; g += pg; b += pb; n += 1
            }
        }
        guard n > 0 else { return nil }

        let ns = NSColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        ns.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        return Color(
            hue: Double(hue),
            saturation: Double(max(sat, 0.38)),
            brightness: Double(max(bri, 0.55))
        )
    }
}

/// List-card background: the usual card surface plus a faint gradient sampled from the poster.
/// Deliberately understated — a wash, not a colour block.
struct PosterTintedCard: View {
    let posterPath: String?
    var cornerRadius: CGFloat = 16

    @State private var tint: Color?

    var body: some View {
        Theme.cardBackground(cornerRadius: cornerRadius)
            .overlay {
                if let tint {
                    LinearGradient(
                        colors: [tint.opacity(0.22), tint.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .task(id: posterPath) {
                let color = await PosterColorCache.shared.color(for: posterPath)
                withAnimation(.easeOut(duration: 0.4)) { tint = color }
            }
    }
}
