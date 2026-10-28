import AppKit
import SwiftUI

extension View {
    /// Resizes the hosting window to the view's ideal height, keeping the top edge fixed.
    /// `MenuBarExtra` windows grow with their content but never shrink on their own.
    func resizesHostingWindowToFit() -> some View {
        modifier(FitWindowToContent())
    }
}

private struct FitWindowToContent: ViewModifier {
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(WindowAccessor(window: $window))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                resize(window, to: size)
            }
            .onChange(of: window) { _, newWindow in
                // The window may only become available after the first layout pass.
                if let newWindow { resize(newWindow, to: newWindow.contentView?.fittingSize) }
            }
    }

    private func resize(_ window: NSWindow?, to size: CGSize?) {
        guard let window, let size, size.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let frame = window.frame
        guard abs(frame.height - target.height) > 0.5 || abs(frame.width - target.width) > 0.5 else { return }
        window.setFrame(NSRect(x: frame.minX, y: frame.maxY - target.height,
                               width: target.width, height: target.height),
                        display: true)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if view.window !== window {
            DispatchQueue.main.async { window = view.window }
        }
    }
}
