import AppKit
import SwiftUI

/// Independent native window; the existing plaza remains behind it.
@MainActor
final class MiiverseWindowController: NSObject, NSWindowDelegate {
    static let frameName = "MacPlazaMiiverseWindow"
    static let minimumSize = NSSize(width: 720, height: 540)
    private weak var model: PlazaModel?
    private let frameAutosaveName: String?
    private(set) var window: NSWindow?
    private var observations: [NSObjectProtocol] = []

    init(model: PlazaModel, frameAutosaveName: String?) {
        self.model = model; self.frameAutosaveName = frameAutosaveName
    }
    func show() {
        guard let model else { return }
        _ = NSApplication.shared
        let window: NSWindow
        if let existing = self.window { window = existing }
        else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Miiverse"; window.identifier = NSUserInterfaceItemIdentifier("MacPlazaMiiverse")
            window.isReleasedWhenClosed = false; window.delegate = self
            window.contentMinSize = Self.minimumSize
            window.collectionBehavior.insert(.fullScreenPrimary)
            self.window = window
            let restored: Bool
            if let name = frameAutosaveName {
                window.setFrameAutosaveName(name); restored = window.setFrameUsingName(name)
            } else { restored = false }
            if !restored {
                let anchor = model.wallpaperEnabled ? model.desktop.window?.frame : model.window?.frame
                let area = anchor ?? NSScreen.main?.visibleFrame ?? window.frame
                window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
            }
            fitToScreen(window)
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.didChangeScreenNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    Task { @MainActor in
                        guard let self, let window = self.window else { return }
                        if note.name == NSWindow.didChangeScreenNotification { self.fitToScreen(window) }
                        self.updateVisibility()
                    }
                })
            }
        }
        // A fresh root resets navigation to all-post Activity Feed on each open.
        if window.attachedSheet == nil {
            window.contentView = NSHostingView(rootView: MiiverseView(model: model, onClose: { [weak self] in self?.close() }))
        }
        window.deminiaturize(nil); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.social.window = window
        updateVisibility()
    }
    func close() {
        guard let window else { return }
        self.window = nil
        observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
        window.delegate = nil; window.contentView = nil; window.close()
        finishClosing()
    }
    func windowWillClose(_ notification: Notification) {
        (notification.object as? NSWindow)?.contentView = nil
        window = nil
        observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
        finishClosing()
    }
    func windowDidBecomeKey(_ notification: Notification) { model?.social.window = window }
    private func finishClosing() {
        guard let model else { return }
        model.miiverseVisible = false; model.audio.stopPreview()
        model.social.window = model.window
        if model.sheet?.id == "miiverse" { model.sheet = nil }
    }
    private func updateVisibility() {
        model?.miiverseVisible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
    }
    private func fitToScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? model?.window?.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, area.width); frame.size.height = min(frame.height, area.height)
        frame.origin.x = max(area.minX, min(frame.minX, area.maxX - frame.width))
        frame.origin.y = max(area.minY, min(frame.minY, area.maxY - frame.height))
        window.setFrame(frame, display: true)
    }
}
