import AppKit
import CoreGraphics
import SwiftUI

/// One desktop renderer. Mii Maker, Friends and Settings float over it; the
/// normal window hosts other sheets without competing for the scene connection.
@MainActor
final class DesktopPlazaController: NSObject, NSWindowDelegate {
    static let preferenceKey = "MacPlaza.WallpaperEnabled"
    private weak var model: PlazaModel?
    private let defaults: UserDefaults
    private(set) var window: DesktopPlazaWindow?
    private(set) var menuWindow: NSPanel?
    private var menuObservations: [NSObjectProtocol] = []
    private var afterMenuLeavesFullScreen:(()->Void)?
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
                       keepAboveDesktopIcons: menuWindow != nil)
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
        PlazaUISounds.shared.play(.back)
        returnToDesktop()
        return nil
    }

    func returnToDesktop(activateFinder: Bool = true) {
        guard let model, model.wallpaperEnabled else { return }
        if menuWindow != nil {model.sheet=nil}
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
        closeMenuWindow()
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
        if model.sheet?.isFloatingMenu == true {presentMenu();return}
        if !companionPresented && menuWindow == nil { interactionBeforeCompanion = model.desktopInteractive }
        closeMenuWindow()
        setInteractive(false)
        companionPresented = true
        model.window?.deminiaturize(nil)
        model.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissCompanionIfNeeded() {
        guard let model, model.wallpaperEnabled, (companionPresented || menuWindow != nil), model.error == nil else { return }
        let wasMenu=menuWindow != nil
        closeMenuWindow()
        companionPresented = false
        model.window?.orderOut(nil)
        setInteractive(interactionBeforeCompanion, activate: wasMenu && interactionBeforeCompanion)
        interactionBeforeCompanion = false
    }

    private func presentMenu() {
        guard let model, let wallpaper=window else{return}
        if !companionPresented && menuWindow == nil {interactionBeforeCompanion=model.desktopInteractive}
        companionPresented=false
        model.window?.orderOut(nil)
        // Keep the same renderer above Finder's icons while the panel owns input.
        setInteractive(false,activate:false,keepAboveDesktopIcons:true)
        let friends = model.sheet?.id == "friends"
        let settings = model.sheet?.id == "preferences"
        let writing = model.sheet?.id == "compose"
        let activity = model.sheet?.id == "activity"
        let miiverse = model.sheet?.id == "miiverse"
        let identifier = settings ? "MacPlazaDesktopSettings" : friends ? "MacPlazaDesktopFriends" : writing ? "MacPlazaDesktopWriteNote" : activity ? "MacPlazaDesktopActivity" : miiverse ? "MacPlazaDesktopMiiverse" : "MacPlazaDesktopMiiMaker"
        if let panel = menuWindow, panel.identifier?.rawValue != identifier { closeMenuWindow() }
        if menuWindow == nil {
            let area=(wallpaper.screen ?? Self.targetScreen)?.visibleFrame ?? wallpaper.frame
            let size=NSSize(width:min(settings || writing || activity ? 760 : 960,area.width-40),height:min(settings || writing ? 820 : 760,area.height-48))
            let panel=NSPanel(contentRect:NSRect(origin:.zero,size:size),
                              styleMask:[.titled,.closable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            panel.title = settings ? "Settings" : friends ? "Friends" : writing ? "Write Note" : activity ? "Activity" : miiverse ? "Miiverse" : "Mii Maker"
            panel.identifier=NSUserInterfaceItemIdentifier(identifier)
            panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
            panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false
            panel.isMovableByWindowBackground=false
            panel.collectionBehavior=[.moveToActiveSpace,.fullScreenPrimary]
            panel.contentMinSize=NSSize(width:640,height:507)
            panel.delegate=self
            panel.contentView=NSHostingView(rootView:DesktopMenuRoot(model:model))
            panel.setFrameOrigin(NSPoint(x:area.midX-panel.frame.width/2,y:area.midY-panel.frame.height/2))
            menuWindow=panel
            for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification] {
                menuObservations.append(NotificationCenter.default.addObserver(forName:name,object:panel,queue:.main) { [weak self] _ in
                    Task { @MainActor in self?.updateMenuVisibility() }
                })
            }
        }
        menuWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        updateMenuVisibility()
    }

    private func updateMenuVisibility() {
        model?.desktopMenuVisible=menuWindow.map {$0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)} ?? false
    }

    private func closeMenuWindow() {
        menuObservations.forEach(NotificationCenter.default.removeObserver);menuObservations=[]
        if let panel=menuWindow {panel.delegate=nil;panel.orderOut(nil);panel.contentView=nil;panel.close()}
        menuWindow=nil;model?.desktopMenuVisible=false;model?.menuFullScreen=false
        afterMenuLeavesFullScreen=nil
    }

    func closeMakerForArrival(_ reveal:@escaping ()->Void) {
        if let panel=menuWindow,panel.styleMask.contains(.fullScreen) {
            afterMenuLeavesFullScreen=reveal
            panel.toggleFullScreen(nil)
        } else {reveal()}
    }

    func windowWillEnterFullScreen(_ notification:Notification) {
        if notification.object as? NSWindow === menuWindow {model?.menuFullScreen=true}
    }
    func windowDidExitFullScreen(_ notification:Notification) {
        guard notification.object as? NSWindow === menuWindow else{return}
        model?.menuFullScreen=false
        let reveal=afterMenuLeavesFullScreen;afterMenuLeavesFullScreen=nil;reveal?()
    }
    func windowDidFailToEnterFullScreen(_ window:NSWindow) {
        if window === menuWindow {model?.menuFullScreen=false}
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
        if sender === menuWindow {model?.sheet=nil;return false}
        returnToDesktop()
        return false
    }

    func shutdown() {
        // Keep the saved preference so the next launch can restore wallpaper mode.
        closeMenuWindow();releaseWindow()
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

private struct DesktopMenuRoot:View {
    @ObservedObject var model:PlazaModel
    var body:some View {
        GeometryReader { proxy in
            let scale=min(1,proxy.size.width/960,proxy.size.height/760)
            Group {
                if model.sheet?.id == "preferences" {
                    PreferencesView(model: model, fillsOverlay: true)
                } else if case .compose(let appID) = model.sheet {
                    ScrollView {
                        NoteComposer(model: model, appID: appID, onClose: { model.sheet = nil })
                            .id(appID).padding(.vertical, 28)
                    }
                } else if model.sheet?.id == "activity" {
                    PlazaActivityView(model: model, social: model.social, onClose: { model.sheet = nil })
                        .scaleEffect(min(1, proxy.size.width/660, proxy.size.height/640))
                } else if model.sheet?.id == "miiverse" {
                    MiiverseView(model: model, onClose: { model.sheet = nil })
                        .scaleEffect(min(1, proxy.size.width/960, proxy.size.height/720))
                } else {
                    Group {
                        if model.sheet?.id == "friends" {
                            FriendsMenuView(model: model, social: model.social, onClose: { model.sheet = nil })
                        } else {
                            MiiMakerView(model:model,onClose:{model.sheet=nil})
                        }
                    }.scaleEffect(scale)
                }
            }
                .frame(width:proxy.size.width,height:proxy.size.height)
        }
        .background(MakerBackground())
        .preferredColorScheme(.light)
        .alert("Mac Plaza",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) {
            PlazaButton("OK") {model.error=nil}
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
            PlazaButton("Interact with Plaza") { model.window?.orderOut(nil); model.desktop.interact() }
                .buttonStyle(.borderedProminent)
            PlazaButton("Open Plaza in Window") { model.desktop.disable() }
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PlazaStyle.paper)
    }
}

/// Editors and activity share a native panel shell above the moving wallpaper.
struct PlazaPanels: ViewModifier {
    @ObservedObject var model: PlazaModel
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get:{model.wallpaperEnabled && model.sheet?.isFloatingMenu == true ? nil:model.sheet},set:{value in
            // Dismissing a previous companion sheet must not close the menu
            // panel that has just replaced it.
            if model.wallpaperEnabled && model.sheet?.isFloatingMenu == true {return}
            model.sheet=value
        })) { sheet in
            Group {
                switch sheet {
                case .characters: MiiMakerView(model: model)
                case .friends: FriendsMenuView(model: model, social: model.social)
                case .profile(let avatar): CharacterProfileView(model: model, avatar: avatar)
                case .friend(let friend): FriendProfileView(model: model, social: model.social, initial: friend)
                case .social: SocialSettingsView(model: model, social: model.social)
                case .compose(let appID): NoteComposer(model: model, appID: appID)
                case .miiverse: MiiverseView(model: model)
                case .activity: PlazaActivityView(model: model, social: model.social)
                case .preferences: PreferencesView(model: model)
                case .app(let app): AppDetailsView(model: model, appID: app.id)
                case .steamGames(let app): SteamGamePicker(model: model, replacing: app)
                }
            }
            .preferredColorScheme(.light)
            .alert("Mac Plaza", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                PlazaButton("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
        .alert("Mac Plaza", isPresented: Binding(get: { model.error != nil && model.sheet == nil }, set: {
            if !$0 && model.sheet == nil { model.error = nil; model.desktop.dismissCompanionIfNeeded() }
        })) {
            PlazaButton("OK") { model.error = nil; model.desktop.dismissCompanionIfNeeded() }
        } message: { Text(model.error ?? "") }
    }
}
