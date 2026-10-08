import SwiftUI

struct MenuBarItem {
    let id: String
    let percents: [String]
    /// Shows a warning sign after the percentages (e.g. rate limited, values are stale).
    var warning = false
}

/// Renders icons + percentages into a template NSImage; MenuBarExtra labels only reliably display a single Image/Text.
struct MenuBarLabel: View {
    let items: [MenuBarItem]

    var body: some View {
        Image(nsImage: render())
    }

    @MainActor private func render() -> NSImage {
        let content = HStack(spacing: 8) {
            ForEach(items, id: \.id) { item in
                HStack(spacing: 3) {
                    ProviderIcon(providerID: item.id).frame(width: 14, height: 14)
                    if item.percents.count > 1 {
                        // Session on top, weekly below.
                        VStack(alignment: .trailing, spacing: -1) {
                            ForEach(Array(item.percents.enumerated()), id: \.offset) { _, p in
                                Text(p).font(.system(size: 8.5, weight: .semibold)).monospacedDigit()
                            }
                        }
                    } else {
                        Text(item.percents.first ?? "–").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    }
                    if item.warning {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .semibold))
                    }
                }
            }
        }
        .fixedSize()
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
