import SwiftUI

/// Floating bottom navigation — a macOS-Dock style bar: an icon with a label per section,
/// the selected one filled with the accent gradient. Sits centered at the bottom of the window.
struct DockBar: View {
    /// Extra bottom padding page content reserves so the last row scrolls clear of the dock.
    static let contentInset: CGFloat = 56

    @Binding var selection: AppSection?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppSection.allCases) { section in
                DockItem(
                    section: section,
                    isSelected: (selection ?? .dashboard) == section
                ) {
                    withAnimation(Motion.smooth) { selection = section }
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }
}

private struct DockItem: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: section.icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(section.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : Color.secondary)
            .frame(width: 78, height: 50)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear))
            )
            .scaleEffect(hovering && !isSelected ? 1.06 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.smooth, value: isSelected)
    }
}
