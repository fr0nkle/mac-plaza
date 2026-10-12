import AppKit
import CoreGraphics
import SwiftUI

/// One desktop renderer. Mii Maker floats over it in a native panel; the normal
/// window hosts other sheets without competing for PlazaScene's connection.
@MainActor
final class DesktopPlazaController: NSObject, NSWindowDelegate {
    static let preferenceKey = "MacPlaza.WallpaperEnabled"
    private weak var model: PlazaModel?
    private let defaults: UserDefaults
    private(set) var window: DesktopPlazaWindow?
    private(set) var makerWindow: NSPanel?
    private var makerObservations: [NSObjectProtocol] = []
    private var afterMakerLeavesFullScreen:(()->Void)?
    private var observations: [NSObjectProtocol] = []
    private var windowObservation: NSObjectProtocol?
    private var escapeMonitor: Any?
    private var restored = false
    private var companionPresented = false
    private var interactionBeforeCompanion = false

    init(model: PlazaModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        super.init()
        observations.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.fitDisplay() } })
    }

    func restoreIfNeeded() {
        guard !restored, let model, model.loaded, model.window != nil else { return }
        restored = true
        // An interrupted session must start with visible recovery controls.
        if !model.demo, (model.loginEnabled || defaults.bool(forKey: Self.preferenceKey)),
           !model.document.preferences.safeMode, !model.recoveryRequired {
            enable(activate: false)
        }
    }

    func enable(interactive: Bool = true, activate: Bool = true) {
        guard let model, model.loaded, model.window != nil else { return }
        guard model.window?.styleMask.contains(.fullScreen) != true else {
            model.error = "Leave full screen before enabling wallpaper mode."
            return
        }
        guard let screen = Self.targetScreen else {
            model.error = "No display is available for wallpaper mode."
            return
        }
        let needsContent = window == nil
        if needsContent {
            let desktop = DesktopPlazaWindow(contentRect: screen.frame, styleMask: .borderless,
                                             backing: .buffered, defer: false)
            desktop.title = "Mac Plaza Wallpaper"
            desktop.identifier = NSUserInterfaceItemIdentifier("MacPlazaWallpaper")
            desktop.isReleasedWhenClosed = false
            desktop.hasShadow = false
            desktop.isOpaque = true
            desktop.backgroundColor = .windowBackgroundColor
            desktop.isMovable = false
            desktop.isMovableByWindowBackground = false
            desktop.hidesOnDeactivate = false
            desktop.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            desktop.delegate = self
            window = desktop
            windowObservation = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: desktop, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.updateVisibility() } }
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyEvent(event)
            }
        }
        // Change the normal window's content before attaching the desktop view.
        model.wallpaperEnabled = true
        model.listMode = false
        model.editing = false
        model.search = ""
        model.previewAppID = nil
        if !model.demo { defaults.set(true, forKey: Self.preferenceKey) }
        fitDisplay()
        if needsContent {
            window?.contentView = DesktopPlazaHostingView(rootView: DesktopPlazaRoot(model: model))
        }
        setInteractive(interactive, activate: false)
        if model.sheet == nil && model.error == nil { model.window?.orderOut(nil) }
        else { presentCompanionIfNeeded() }
        setInteractive(interactive && model.sheet == nil && model.error == nil, activate: activate,
                       keepAboveDesktopIcons: makerWindow != nil)
        window?.orderFrontRegardless()
        updateVisibility()
        model.updateAudio()
    }

    func interact() {
        enable(interactive: true)
    }

    /// Return from a menu without resetting the current app page or edit mode.
    func resumeInteraction() {
        guard let model, model.wallpaperEnabled else { return }
        guard window != nil else { enable(); return }
        setInteractive(true)
    }

    func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown, event.keyCode == 53, model?.desktopInteractive == true,
              event.window === window else { return event }
        returnToDesktop()
        return nil
    }

    func returnToDesktop(activateFinder: Bool = true) {
        guard let model, model.wallpaperEnabled else { return }
        if makerWindow != nil {model.sheet=nil}
        let wasInteractive = model.desktopInteractive
        model.previewAppID = nil
        model.editing = false
        setInteractive(false)
        if wasInteractive && activateFinder {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
                .first?.activate(options: [])
        }
    }

    func disable(showWindow: Bool = true) {
        guard let model else { return }
        model.desktopInteractive = false
        model.wallpaperEnabled = false
        model.desktopVisible = false
        companionPresented = false
        interactionBeforeCompanion = false
        closeMakerWindow()
        if !model.demo { defaults.set(false, forKey: Self.preferenceKey) }
        releaseWindow()
        if showWindow {
            model.window?.deminiaturize(nil)
            model.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        model.updateAudio()
    }

    func presentCompanionIfNeeded() {
        guard let model, model.wallpaperEnabled else { return }
        if model.sheet?.id == "characters" {presentMaker();return}
        if !companionPresented && makerWindow == nil { interactionBeforeCompanion = model.desktopInteractive }
        closeMakerWindow()
        setInteractive(false)
        companionPresented = true
        model.window?.deminiaturize(nil)
        model.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissCompanionIfNeeded() {
        guard let model, model.wallpaperEnabled, (companionPresented || makerWindow != nil), model.error == nil else { return }
        let wasMaker=makerWindow != nil
        closeMakerWindow()
        companionPresented = false
        model.window?.orderOut(nil)
        setInteractive(interactionBeforeCompanion, activate: wasMaker && interactionBeforeCompanion)
        interactionBeforeCompanion = false
    }

    private func presentMaker() {
        guard let model, let wallpaper=window else{return}
        if !companionPresented && makerWindow == nil {interactionBeforeCompanion=model.desktopInteractive}
        companionPresented=false
        model.window?.orderOut(nil)
        // Keep the same renderer above Finder's icons while the panel owns input.
        setInteractive(false,activate:false,keepAboveDesktopIcons:true)
        if makerWindow == nil {
            let area=(wallpaper.screen ?? Self.targetScreen)?.visibleFrame ?? wallpaper.frame
            let size=NSSize(width:min(960,area.width-40),height:min(760,area.height-48))
            let panel=NSPanel(contentRect:NSRect(origin:.zero,size:size),
                              styleMask:[.titled,.closable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            panel.title="Mii Maker"
            panel.identifier=NSUserInterfaceItemIdentifier("MacPlazaDesktopMiiMaker")
            panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
            panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false
            panel.isMovableByWindowBackground=false
            panel.collectionBehavior=[.moveToActiveSpace,.fullScreenPrimary]
            panel.contentMinSize=NSSize(width:640,height:507)
            panel.delegate=self
            panel.contentView=NSHostingView(rootView:DesktopMiiMakerRoot(model:model))
            panel.setFrameOrigin(NSPoint(x:area.midX-panel.frame.width/2,y:area.midY-panel.frame.height/2))
            makerWindow=panel
            for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification] {
                makerObservations.append(NotificationCenter.default.addObserver(forName:name,object:panel,queue:.main) { [weak self] _ in
                    Task { @MainActor in self?.updateMakerVisibility() }
                })
            }
        }
        makerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        updateMakerVisibility()
    }

    private func updateMakerVisibility() {
        model?.desktopMakerVisible=makerWindow.map {$0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)} ?? false
    }

    private func closeMakerWindow() {
        makerObservations.forEach(NotificationCenter.default.removeObserver);makerObservations=[]
        if let panel=makerWindow {panel.delegate=nil;panel.orderOut(nil);panel.contentView=nil;panel.close()}
        makerWindow=nil;model?.desktopMakerVisible=false;model?.makerFullScreen=false
        afterMakerLeavesFullScreen=nil
    }

    func closeMakerForArrival(_ reveal:@escaping ()->Void) {
        if let panel=makerWindow,panel.styleMask.contains(.fullScreen) {
            afterMakerLeavesFullScreen=reveal
            panel.toggleFullScreen(nil)
        } else {reveal()}
    }

    func windowWillEnterFullScreen(_ notification:Notification) {
        if notification.object as? NSWindow === makerWindow {model?.makerFullScreen=true}
    }
    func windowDidExitFullScreen(_ notification:Notification) {
        guard notification.object as? NSWindow === makerWindow else{return}
        model?.makerFullScreen=false
        let reveal=afterMakerLeavesFullScreen;afterMakerLeavesFullScreen=nil;reveal?()
    }
    func windowDidFailToEnterFullScreen(_ window:NSWindow) {
        if window === makerWindow {model?.makerFullScreen=false}
    }

    private func setInteractive(_ interactive: Bool, activate: Bool = true, keepAboveDesktopIcons:Bool=false) {
        guard let model, let window else { return }
        model.desktopInteractive = interactive
        window.interactive = interactive
        window.ignoresMouseEvents = !interactive
        window.level = Self.level(interactive: interactive || keepAboveDesktopIcons)
        if interactive && activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if !interactive && window.isKeyWindow && !keepAboveDesktopIcons {
            window.orderOut(nil)
            window.orderFrontRegardless()
        }
        updateVisibility()
    }

    static func level(interactive: Bool) -> NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + (interactive ? 1 : -1))
    }

    static var targetScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        } ?? NSScreen.screens.first
    }

    private func fitDisplay() {
        guard let model, let window, let screen = Self.targetScreen else { return }
        let frame = screen.frame, visible = screen.visibleFrame
        // The background covers the screen; controls stay outside the menu bar and Dock.
        model.desktopInsets = EdgeInsets(top: max(16, frame.maxY - visible.maxY + 12),
            leading: max(12, visible.minX - frame.minX + 12),
            bottom: max(32, visible.minY - frame.minY + 12),
            trailing: max(12, frame.maxX - visible.maxX + 12))
        window.setFrame(frame, display: true)
        updateVisibility()
    }

    private func updateVisibility() {
        model?.desktopVisible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === makerWindow {model?.sheet=nil;return false}
        returnToDesktop()
        return false
    }

    func shutdown() {
        // Keep the saved preference so the next launch can restore wallpaper mode.
        closeMakerWindow();releaseWindow()
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
    }

    private func releaseWindow() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        if let windowObservation { NotificationCenter.default.removeObserver(windowObservation); self.windowObservation = nil }
        if let window {
            window.delegate = nil
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        window = nil
    }
}

private struct DesktopMiiMakerRoot:View {
    @ObservedObject var model:PlazaModel
    var body:some View {
        GeometryReader { proxy in
            let scale=min(1,proxy.size.width/960,proxy.size.height/760)
            MiiMakerView(model:model,onClose:{model.sheet=nil})
                .scaleEffect(scale)
                .frame(width:proxy.size.width,height:proxy.size.height)
        }
        .background(MakerBackground())
        .preferredColorScheme(.light)
        .alert("Mac Plaza",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) {
            Button("OK") {model.error=nil}
        } message: {Text(model.error ?? "")}
    }
}

final class DesktopPlazaHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DesktopPlazaWindow: NSWindow {
    var interactive = false
    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { false }
}

private struct DesktopPlazaRoot: View {
    @ObservedObject var model: PlazaModel
    var body: some View {
        PlazaView(model: model, desktop: true)
            .padding(model.desktopInsets)
            .background(PlazaStyle.paper)
            .ignoresSafeArea()
            .allowsHitTesting(model.desktopInteractive)
            .accessibilityHidden(!model.desktopInteractive)
    }
}

struct WallpaperCompanionView: View {
    @ObservedObject var model: PlazaModel
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sun.max").font(.system(size: 44)).foregroundStyle(PlazaStyle.teal)
            Text("Your plaza is on the desktop").font(.title2)
            Text("Click the plaza’s buttons, apps and characters directly. Press Escape to return to your desktop files; use Interact with Plaza in the menu bar to resume.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Interact with Plaza") { model.window?.orderOut(nil); model.desktop.interact() }
                .buttonStyle(.borderedProminent)
            Button("Open Plaza in Window") { model.desktop.disable() }
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PlazaStyle.paper)
    }
}

/// Wallpaper Mii Maker uses its own panel; other sheets use the normal window.
struct PlazaPanels: ViewModifier {
    @ObservedObject var model: PlazaModel
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get:{model.wallpaperEnabled && model.sheet?.id == "characters" ? nil:model.sheet},set:{value in
            // Dismissing a previous companion sheet must not close the maker
            // panel that has just replaced it.
            if model.wallpaperEnabled && model.sheet?.id == "characters" {return}
            model.sheet=value
        })) { sheet in
            Group {
                switch sheet {
                case .characters: MiiMakerView(model: model)
                case .profile(let avatar): CharacterProfileView(model: model, avatar: avatar)
                case .friend(let friend): FriendProfileView(model: model, social: model.social, initial: friend)
                case .social: SocialSettingsView(model: model, social: model.social)
                case .compose(let appID): NoteComposer(model: model, appID: appID)
                case .feed: FeedView(model: model)
                case .preferences: PreferencesView(model: model)
                case .app(let app): AppDetailsView(model: model, appID: app.id)
                }
            }
            .preferredColorScheme(.light)
            .alert("Mac Plaza", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
        .alert("Mac Plaza", isPresented: Binding(get: { model.error != nil && model.sheet == nil }, set: {
            if !$0 && model.sheet == nil { model.error = nil; model.desktop.dismissCompanionIfNeeded() }
        })) {
            Button("OK") { model.error = nil; model.desktop.dismissCompanionIfNeeded() }
        } message: { Text(model.error ?? "") }
    }
}
