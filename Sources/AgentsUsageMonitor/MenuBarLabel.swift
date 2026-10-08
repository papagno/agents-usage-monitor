import SwiftUI

/// Renders icons + percentages into a template NSImage; MenuBarExtra labels only reliably display a single Image/Text.
struct MenuBarLabel: View {
    let items: [(id: String, percent: String)]

    var body: some View {
        Image(nsImage: render())
    }

    @MainActor private func render() -> NSImage {
        let content = HStack(spacing: 8) {
            ForEach(items, id: \.id) { item in
                HStack(spacing: 3) {
                    ProviderIcon(providerID: item.id).frame(width: 14, height: 14)
                    Text(item.percent).font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 1)
        .frame(height: 18)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cg = renderer.cgImage else { return NSImage() }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / renderer.scale,
                                                      height: CGFloat(cg.height) / renderer.scale))
        image.isTemplate = true
        return image
    }
}
