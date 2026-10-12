import AppKit
import SwiftUI

/// Give fixed plaza controls their own native surface above the WebKit/SceneKit
/// floor. Drawing a SwiftUI overlay alone does not guarantee AppKit hit order.
/// Keep this surface tightly sized to its control so the rest of the floor
/// remains available for character selection and camera navigation.
struct PlazaControlSurface<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> PlazaControlHostingView {
        PlazaControlHostingView(rootView: AnyView(content().preferredColorScheme(.light)))
    }

    func updateNSView(_ view: PlazaControlHostingView, context: Context) {
        view.rootView = AnyView(content().preferredColorScheme(.light))
    }
}

class PlazaControlHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The ordinary plaza allows dragging its background to move the window.
    // Buttons and app drags must retain their mouse-down instead.
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        if let window, window.canBecomeKey, !window.isKeyWindow {
            window.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        super.mouseDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point) ?? self
    }
}
