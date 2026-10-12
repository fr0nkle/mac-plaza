import AppKit
import SwiftUI

/// App arrangement stays inside the plaza window. A local mouse gesture avoids
/// handing desktop-level windows to the system's external-file drag session.
struct PlazaAppControlSurface<Content: View>: NSViewRepresentable {
    let appID: UUID
    let enabled: Bool
    let select: () -> Void
    let move: (UUID, UUID) -> Bool
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> PlazaAppHostingView {
        let view = PlazaAppHostingView(rootView: AnyView(content().preferredColorScheme(.light)))
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: PlazaAppHostingView, context: Context) {
        view.rootView = AnyView(content().preferredColorScheme(.light))
        view.appID = appID; view.dragEnabled = enabled
        view.selectApp = select; view.moveApp = move
    }
    static func dismantleNSView(_ view: PlazaAppHostingView, coordinator: ()) { view.cancelDrag() }
}

final class PlazaAppHostingView: PlazaControlHostingView {
    var appID = UUID()
    var dragEnabled = false { didSet { if !dragEnabled { cancelDrag() } } }
    var selectApp: (() -> Void)?
    var moveApp: ((UUID, UUID) -> Bool)?
    private var start: NSPoint?
    private(set) var dragging = false
    private var preview: PlazaDragImage?
    private var previewOrigin = NSPoint.zero
    private var outline: PlazaDragOutline?
    private weak var target: PlazaAppHostingView?
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard dragEnabled else { super.mouseDown(with: event); return }
        window?.makeKey(); window?.makeFirstResponder(self)
        NSApp.activate(ignoringOtherApps: true)
        beginDrag(at: event.locationInWindow)
    }
    override func mouseDragged(with event: NSEvent) {
        guard start != nil else { super.mouseDragged(with: event); return }
        updateDrag(at: event.locationInWindow)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { super.mouseUp(with: event); return }
        endDrag(at: event.locationInWindow)
    }
    override func cancelOperation(_ sender: Any?) { cancelDrag() }

    func beginDrag(at point: NSPoint) {
        cancelDrag()
        guard dragEnabled else { return }
        start = point
    }
    func updateDrag(at point: NSPoint) {
        guard dragEnabled, let start, let content = window?.contentView else { cancelDrag(); return }
        let delta = NSSize(width: point.x - start.x, height: point.y - start.y)
        guard dragging || hypot(delta.width, delta.height) >= 8 else { return }
        if !dragging {
            dragging = true
            if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
                cacheDisplay(in: bounds, to: rep)
                let image = NSImage(size: bounds.size); image.addRepresentation(rep)
                let view = PlazaDragImage(frame: convert(bounds, to: content))
                view.image = image; view.imageScaling = .scaleAxesIndependently
                view.alphaValue = 0.85; view.setAccessibilityElement(false)
                previewOrigin = view.frame.origin; content.addSubview(view)
                preview = view
            }
            alphaValue = 0.45
        }
        // Convert both points so this also follows scaled or flipped hosts.
        let a = content.convert(start, from: nil), b = content.convert(point, from: nil)
        preview?.setFrameOrigin(NSPoint(x: previewOrigin.x + b.x - a.x, y: previewOrigin.y + b.y - a.y))
        setTarget(dropTarget(at: point))
    }
    func endDrag(at point: NSPoint) {
        guard start != nil else { return }
        let destination = dragging && dragEnabled ? dropTarget(at: point)?.appID : nil
        let clicked = !dragging && dragEnabled && bounds.contains(convert(point, from: nil))
        cancelDrag()
        if let destination { _ = moveApp?(appID, destination) }
        else if clicked { selectApp?() }
    }
    func cancelDrag() {
        start = nil; dragging = false; alphaValue = 1
        preview?.removeFromSuperview(); preview = nil
        setTarget(nil)
    }
    private func dropTarget(at point: NSPoint) -> PlazaAppHostingView? {
        guard let content = window?.contentView else { return nil }
        let local = content.convert(point, from: nil)
        var hit = content.hitTest(content.convert(local, to: content.superview))
        while let view = hit {
            if let app = view as? PlazaAppHostingView {
                return app !== self && app.dragEnabled ? app : nil
            }
            hit = view.superview
        }
        return nil
    }
    private func setTarget(_ view: PlazaAppHostingView?) {
        guard view !== target || (view == nil && outline != nil) else { return }
        outline?.removeFromSuperview(); outline = nil; target = view
        if let view {
            let border = PlazaDragOutline(frame: view.bounds)
            border.autoresizingMask = [.width, .height]; border.wantsLayer = true
            border.layer?.borderColor = NSColor.systemTeal.cgColor
            border.layer?.borderWidth = 3; border.layer?.cornerRadius = 24
            border.setAccessibilityElement(false)
            view.addSubview(border); outline = border
        }
    }
}

private final class PlazaDragImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
private final class PlazaDragOutline: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
