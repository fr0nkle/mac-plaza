import SwiftUI
import AppKit

@main
struct MacPlazaApp: App {
    @StateObject private var model = PlazaModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("social.setupSeen") private var setupSeen = false
    var body: some Scene {
        Window("Mac Plaza", id: "plaza") {
            Group {
                if model.wallpaperEnabled { WallpaperCompanionView(model: model) }
                else { PlazaView(model: model) }
            }
                .modifier(PlazaPanels(model: model))
                .background(WindowConnection(model: model))
                .onAppear { delegate.model = model; model.desktop.restoreIfNeeded(); model.offerDiagnosticsAfterInterruptedSession() }
                .onChange(of: model.loaded) { _, loaded in
                    model.desktop.restoreIfNeeded()
                    if loaded, !setupSeen, !model.social.hasSession, !CommandLine.arguments.contains("--demo"), !model.recoveryRequired, !model.previousSessionInterrupted {
                        setupSeen = true; model.sheet = .social
                    }
                }
        }
        .defaultSize(width: 1280, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) { CheckForPlazaUpdates() }
            CommandGroup(replacing: .newItem) {
                PlazaButton("Add Application…") { show(); model.pickApp() }.keyboardShortcut("n", modifiers: .command)
                PlazaButton("Add Steam Game…") { present(.steamGames(nil)) }
                PlazaButton("New Miiverse Post…") { present(.compose(nil)) }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                PlazaButton("Preferences…") { present(.preferences) }.keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Plaza") {
                PlazaButton("Show Plaza") { show() }.keyboardShortcut("1", modifiers: .command)
                PlazaButton("Change Apps") { if !model.wallpaperEnabled { show() }; model.beginChangingApps() }
                wallpaperControls
                Divider()
                PlazaButton("Miiverse") { if !model.wallpaperEnabled { show() }; model.openMiiverse() }.keyboardShortcut("j", modifiers: .command)
                PlazaButton("Your Character Profile") { present(.profile(model.document.primaryAvatar)) }.keyboardShortcut("e", modifiers:[.command,.shift])
                PlazaButton("Friends") { present(.friends) }.keyboardShortcut("f", modifiers: [.command, .shift])
                PlazaButton("Characters") { present(.characters) }.keyboardShortcut("e", modifiers: .command)
                PlazaButton(model.listMode ? "Show Animated Plaza" : "Show Accessible List") { show(); model.listMode.toggle() }.keyboardShortcut("l", modifiers: .command)
                PlazaButton(model.document.preferences.pauseMotion ? "Resume Motion" : "Pause Motion") { model.mutate { $0.preferences.pauseMotion.toggle() } }.keyboardShortcut("p", modifiers: .command)
                Divider()
                PlazaButton("Undo Layout Change") { model.undoLayout() }.keyboardShortcut("z", modifiers: .command)
            }
        }
        MenuBarExtra("Mac Plaza", systemImage: "sun.max") {
            PlazaButton("Open Plaza in Window") { show() }
            wallpaperControls
            Divider()
            PlazaButton(model.document.preferences.pauseMotion ? "Resume Motion" : "Pause Motion") { model.mutate { $0.preferences.pauseMotion.toggle() } }
            PlazaButton("Miiverse") { if !model.wallpaperEnabled { show() }; model.openMiiverse() }
            PlazaButton("Friends…") { present(.friends) }
            PlazaButton("Characters…") { present(.characters) }
            PlazaButton("Preferences…") { present(.preferences) }
            CheckForPlazaUpdates()
            Divider()
            PlazaButton("Quit Mac Plaza") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
    @ViewBuilder private var wallpaperControls: some View {
        Toggle("Use as Wallpaper", isOn: Binding(get: { model.wallpaperEnabled }, set: { enabled in
            if enabled { model.desktop.enable() } else { model.desktop.disable() }
        })).disabled(!model.loaded)
        PlazaButton("Interact with Plaza") { model.desktop.interact() }.disabled(!model.loaded || model.sheet != nil)
        PlazaButton("Return to Desktop (Escape)") { model.desktop.returnToDesktop() }.disabled(!model.desktopInteractive)
        if let reason = model.automaticMusicMuteReason { Text(reason) }
        PlazaButton(model.document.preferences.ambientSound == false ? "Unmute Music" : "Mute Music") {
            model.mutate { $0.preferences.ambientSound = !($0.preferences.ambientSound ?? true) }
            model.updateAudio()
            if model.document.preferences.ambientSound == false { model.audio.stopPreview() }
        }
    }
    private func show() {
        if model.wallpaperEnabled { model.desktop.disable() }
        openWindow(id: "plaza")
        NSApp.activate(ignoringOtherApps: true)
        model.window?.deminiaturize(nil)
        model.window?.makeKeyAndOrderFront(nil)
    }
    private func present(_ sheet: PlazaSheet) {
        if !model.wallpaperEnabled { show() }
        model.sheet = sheet
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: PlazaModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.desktop.shutdown()
        model.birthdayCelebration.dismiss()
        model.miiverseWindow.close()
        Task { model.social.setActive(false); await model.flush(); try? await model.storage.endSession(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model?.wallpaperEnabled == true { model?.desktop.interact(); return true }
        if !flag { model?.window?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct WindowConnection: NSViewRepresentable {
    let model: PlazaModel
    func makeNSView(context: Context) -> WindowObserverView { WindowObserverView(model: model) }
    func updateNSView(_ nsView: WindowObserverView, context: Context) {}
}
final class WindowObserverView: NSView {
    weak var model: PlazaModel?
    var tokens: [NSObjectProtocol] = []
    init(model: PlazaModel) { self.model = model; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        model?.window = window
        model?.social.window = window
        window.setFrameAutosaveName("MacPlazaMainWindow")
        window.setFrameUsingName("MacPlazaMainWindow")
        clamp(window)
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        model?.windowVisible = window.isVisible && window.occlusionState.contains(.visible) && !window.isMiniaturized
        Task { @MainActor [weak model] in model?.desktop.restoreIfNeeded(); model?.offerDiagnosticsAfterInterruptedSession() }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification, NSWindow.didChangeScreenNotification, NSWindow.didEndSheetNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] notification in
                Task { @MainActor in
                    if notification.name == NSWindow.didChangeScreenNotification,let window { self?.clamp(window) }
                    self?.model?.windowVisible = notification.name != NSWindow.willCloseNotification && (window?.occlusionState.contains(.visible) ?? false) && !(window?.isMiniaturized ?? true)
                    if notification.name == NSWindow.didEndSheetNotification { self?.model?.offerDiagnosticsAfterInterruptedSession() }
                }
            })
        }
    }
    private func clamp(_ window: NSWindow) {
        guard let screen=window.screen ?? NSScreen.main else { return }; let area=screen.visibleFrame; var f=window.frame
        f.size.width=min(f.width,area.width); f.size.height=min(f.height,area.height)
        f.origin.x=max(area.minX,min(f.minX,area.maxX-f.width)); f.origin.y=max(area.minY,min(f.minY,area.maxY-f.height))
        if f != window.frame { window.setFrame(f,display:true) }
    }
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}
