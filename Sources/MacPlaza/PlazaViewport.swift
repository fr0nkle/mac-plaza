import Foundation
import SwiftUI
import AppKit
import PlazaCore

/// One transform for the floor, native app tiles and both character renderers.
struct PlazaViewport {
    static let zoomRange: ClosedRange<CGFloat> = 0.75...1.75
    static func zoom(_ value: CGFloat) -> CGFloat {
        min(zoomRange.upperBound, max(zoomRange.lowerBound, value))
    }
    /// A shared camera move keeps the selected tile and nearby walkers together.
    /// Position the app on the left, leaving the right side for its speech bubble.
    static func appFocus(at point: CGPoint, size: CGSize) -> (zoom: CGFloat, offset: CGSize) {
        let scale = min(2.1, max(1.8, size.height * 0.40 / PlazaLayout.tileSize(in: size)))
        let target = CGPoint(x: size.width * 0.28, y: size.height * 0.25)
        return (scale, CGSize(width: target.x - size.width / 2 - (point.x - 0.5) * size.width * scale,
                              height: target.y - size.height / 2 - (point.y - 0.5) * size.height * scale))
    }
    static func offset(_ value: CGSize, zoom: CGFloat, size: CGSize) -> CGSize {
        let x = max(0, (zoom - 1) * size.width / 2)
        let y = max(0, (zoom - 1) * size.height / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
    static func arrivalFocus(elapsed:Double,zoom:CGFloat,offset:CGSize,size:CGSize)->(zoom:CGFloat,offset:CGSize) {
        let amount=CGFloat(PlazaCore.PlazaArrival.focus(at:elapsed))
        let closeZoom:CGFloat=4.8
        let closeOffset=CGSize(width:0,height:-size.height*0.015*closeZoom)
        // Interpolate magnification perceptually rather than rushing through
        // the wide view with a linear scale change.
        let scale=exp(log(zoom)+(log(closeZoom)-log(zoom))*amount)
        return (scale,
                CGSize(width:offset.width+(closeOffset.width-offset.width)*amount,
                       height:offset.height+(closeOffset.height-offset.height)*amount))
    }
}

/// Native WebKit and SceneKit views receive mouse events before SwiftUI
/// gestures. Observe this window's events so navigation works on either floor.
struct PlazaNavigationInput: NSViewRepresentable {
    let enabled: Bool
    let canPan: Bool
    let zoom: CGFloat
    let offset: CGSize
    let onZoom: (CGFloat) -> Void
    let onPan: (CGSize) -> Void
    func makeNSView(context: Context) -> NavigationView { NavigationView() }
    func updateNSView(_ view: NavigationView, context: Context) {
        view.enabled=enabled;view.canPan=canPan;view.zoom=zoom;view.offset=offset
        view.onZoom=onZoom;view.onPan=onPan
    }
    static func dismantleNSView(_ view: NavigationView, coordinator: ()) { view.stop() }

    final class NavigationView: NSView {
        var enabled=false,canPan=false,zoom:CGFloat=1,offset=CGSize.zero
        var onZoom:((CGFloat)->Void)?,onPan:((CGSize)->Void)?
        private var monitor:Any?,start:CGPoint?,origin=CGSize.zero,dragging=false
        override var isFlipped:Bool {true}
        override func hitTest(_ point:NSPoint)->NSView? {nil}
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow();stop()
            guard window != nil else{return}
            monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp,.magnify,.keyDown]) { [weak self] event in
                guard let self else{return event}
                return self.handle(event)
            }
        }
        func stop() {if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil;start=nil;dragging=false}
        func handle(_ event:NSEvent)->NSEvent? {
            guard enabled,let window,event.window===window else{return event}
            let point=convert(event.locationInWindow,from:nil)
            switch event.type {
            case .keyDown:
                guard event.modifierFlags.intersection([.command,.control,.option]) == .command else{return event}
                switch event.charactersIgnoringModifiers {
                case "=","+":onZoom?(zoom+0.15);return nil
                case "-":onZoom?(zoom-0.15);return nil
                case "0":onZoom?(1);onPan?(.zero);return nil
                default:return event
                }
            case .magnify:
                guard bounds.contains(point) else{return event}
                onZoom?(zoom*(1+event.magnification));return nil
            case .leftMouseDown:
                start=nil;dragging=false
                if canPan && zoom>1 && bounds.contains(point) && !isControlEvent(event) {
                    start=point;origin=offset
                }
            case .leftMouseDragged:
                guard let start,canPan,zoom>1 else{return event}
                let dx=point.x-start.x,dy=point.y-start.y
                if hypot(dx,dy)>8 {dragging=true}
                if dragging {onPan?(CGSize(width:origin.width+dx,height:origin.height+dy));return nil}
            case .leftMouseUp:
                let consumed=dragging;start=nil;dragging=false
                if consumed{return nil}
            default:break
            }
            return event
        }
        private func isControlEvent(_ event:NSEvent)->Bool {
            guard let content=window?.contentView else{return false}
            let point=content.convert(event.locationInWindow,from:nil)
            var hit=content.hitTest(content.convert(point,to:content.superview))
            while let view=hit {
                if view is PlazaControlHostingView{return true}
                hit=view.superview
            }
            return false
        }
        deinit {if let monitor{NSEvent.removeMonitor(monitor)}}
    }
}
