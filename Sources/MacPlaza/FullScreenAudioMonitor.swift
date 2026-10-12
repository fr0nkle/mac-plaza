import AppKit
import CoreGraphics
import OSLog

/// Detect a foreground app covering an entire display using window geometry.
/// This needs no screen capture, window titles or Accessibility permission.
@MainActor
final class FullScreenAudioMonitor {
    struct State: Equatable {
        var fullScreen = false
        var coversPlaza = false
    }
    private var presentationObservation: NSKeyValueObservation?
    private var observations: [NSObjectProtocol] = []
    private var settleTask: Task<Void, Never>?
    private var timer: Timer?
    private let onChange: (State) -> Void
    private let plazaScreen: () -> NSScreen?
    private var lastValue: State?
    private let logger = Logger(subsystem: "local.macplaza.audio", category: "FullScreen")

    init(plazaScreen: @escaping () -> NSScreen? = { NSScreen.main }, onChange: @escaping (State) -> Void) {
        self.plazaScreen = plazaScreen
        self.onChange = onChange
        presentationObservation = NSApplication.shared.observe(\.currentSystemPresentationOptions, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshAfterTransition() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observations.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshAfterTransition() }
            })
        }
        // Full-screen presentation options can stay stale in an inactive app.
        // Notifications plus a low-frequency geometry check cover that case.
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshAfterTransition()
    }

    static func shouldMute(frontmostPID: pid_t?, ownPID: pid_t, coversDisplay: Bool) -> Bool {
        guard let frontmostPID, frontmostPID != ownPID else { return false }
        return coversDisplay
    }

    static func coversDisplay(window: CGRect, display: CGRect, topInset: CGFloat = 0) -> Bool {
        guard !window.isEmpty, !display.isEmpty else { return false }
        let tolerance: CGFloat = 2
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
        return near(window.minX, display.minX) && near(window.maxX, display.maxX) && near(window.maxY, display.maxY) &&
            (near(window.minY, display.minY) || (topInset > 0 && near(window.minY, display.minY + topInset)))
    }

    static func coversMostOfPlaza(window: CGRect, usableArea: CGRect) -> Bool {
        guard !usableArea.isEmpty, !window.isEmpty else { return false }
        let overlap = window.intersection(usableArea)
        return !overlap.isNull && overlap.width * overlap.height >= usableArea.width * usableArea.height * 0.85
    }

    private func foregroundCoverage(_ pid: pid_t) -> State {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return State() }
        let displays = NSScreen.screens.compactMap { screen -> (CGRect, CGFloat)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            // Quartz uses a top-left origin; CGDisplayBounds matches window
            // dictionaries, including displays above/left of the main screen.
            return (CGDisplayBounds(number.uint32Value), screen.safeAreaInsets.top)
        }
        let usableArea = plazaScreen().flatMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let display = CGDisplayBounds(number.uint32Value), visible = screen.visibleFrame, frame = screen.frame
            return CGRect(x: display.minX + visible.minX - frame.minX,
                          y: display.minY + frame.maxY - visible.maxY,
                          width: visible.width, height: visible.height)
        }
        var result = State()
        for info in windows {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                  let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { continue }
            if displays.contains(where: { Self.coversDisplay(window: bounds, display: $0.0, topInset: $0.1) }) { result.fullScreen = true }
            if let usableArea, Self.coversMostOfPlaza(window: bounds, usableArea: usableArea) { result.coversPlaza = true }
        }
        return result
    }

    private func refresh() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let state = pid.flatMap { $0 != ownPID ? foregroundCoverage($0) : nil } ?? State()
        guard state != lastValue else { return }
        lastValue = state
        logger.notice("Window music suppression: full-screen=\(state.fullScreen, privacy: .public), covered=\(state.coversPlaza, privacy: .public)")
        onChange(state)
    }

    private func refreshAfterTransition() {
        refresh()
        settleTask?.cancel()
        // Space animations and activation can arrive before the presentation
        // mode settles. These bounded checks also handle returning to desktop.
        settleTask = Task { @MainActor [weak self] in
            for delay in [0.25, 0.75] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                self?.refresh()
            }
        }
    }

    deinit {
        settleTask?.cancel()
        timer?.invalidate()
        presentationObservation?.invalidate()
        observations.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }
}
