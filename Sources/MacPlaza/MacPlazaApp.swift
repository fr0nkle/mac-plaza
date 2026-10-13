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
                .onAppear { delegate.model = model; model.desktop.restoreIfNeeded() }
                .onChange(of: model.loaded) { _, loaded in
                    model.desktop.restoreIfNeeded()
                    if loaded, !setupSeen, !model.social.hasSession, !CommandLine.arguments.contains("--demo"), !model.recoveryRequired {
                        setupSeen = true; model.sheet = .social
                    }
                }
        }
        .defaultSize(width: 1280, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) { CheckForPlazaUpdates() }
            CommandGroup(replacing: .newItem) {
                Button("Add Application…") { show(); model.pickApp() }.keyboardShortcut("n", modifiers: .command)
                Button("Add Steam Game…") { present(.steamGames(nil)) }
                Button("New Local Note…") { present(.compose(nil)) }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") { present(.preferences) }.keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Plaza") {
                Button("Show Plaza") { show() }.keyboardShortcut("1", modifiers: .command)
                Button("Change Apps") { if !model.wallpaperEnabled { show() }; model.beginChangingApps() }
                wallpaperControls
                Divider()
                Button("Plaza Journal") { if !model.wallpaperEnabled { show() }; model.openJournal() }.keyboardShortcut("j", modifiers: .command)
                Button("Your Character Profile") { present(.profile(model.document.primaryAvatar)) }.keyboardShortcut("e", modifiers:[.command,.shift])
                Button("Friends") { present(.friends) }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Characters") { present(.characters) }.keyboardShortcut("e", modifiers: .command)
                Button(model.listMode ? "Show Animated Plaza" : "Show Accessible List") { show(); model.listMode.toggle() }.keyboardShortcut("l", modifiers: .command)
                Button(model.document.preferences.pauseMotion ? "Resume Motion" : "Pause Motion") { model.mutate { $0.preferences.pauseMotion.toggle() } }.keyboardShortcut("p", modifiers: .command)
                Divider()
                Button("Undo Layout Change") { model.undoLayout() }.keyboardShortcut("z", modifiers: .command)
            }
        }
        MenuBarExtra("Mac Plaza", systemImage: "sun.max") {
            Button("Open Plaza in Window") { show() }
            wallpaperControls
            Divider()
            Button(model.document.preferences.pauseMotion ? "Resume Motion" : "Pause Motion") { model.mutate { $0.preferences.pauseMotion.toggle() } }
            Button("Plaza Journal") { if !model.wallpaperEnabled { show() }; model.openJournal() }
            Button("Friends…") { present(.friends) }
            Button("Characters…") { present(.characters) }
            Button("Preferences…") { present(.preferences) }
            CheckForPlazaUpdates()
            Divider()
            Button("Quit Mac Plaza") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
    @ViewBuilder private var wallpaperControls: some View {
        Toggle("Use as Wallpaper", isOn: Binding(get: { model.wallpaperEnabled }, set: { enabled in
            if enabled { model.desktop.enable() } else { model.desktop.disable() }
        })).disabled(!model.loaded)
        Button("Interact with Plaza") { model.desktop.interact() }.disabled(!model.loaded || model.sheet != nil)
        Button("Return to Desktop (Escape)") { model.desktop.returnToDesktop() }.disabled(!model.desktopInteractive)
        if let reason = model.automaticMusicMuteReason { Text(reason) }
        Button(model.document.preferences.ambientSound == false ? "Unmute Music" : "Mute Music") {
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
        Task { @MainActor [weak model] in model?.desktop.restoreIfNeeded() }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification, NSWindow.didChangeScreenNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] notification in
                Task { @MainActor in
                    if notification.name == NSWindow.didChangeScreenNotification,let window { self?.clamp(window) }
                    self?.model?.windowVisible = notification.name != NSWindow.willCloseNotification && (window?.occlusionState.contains(.visible) ?? false) && !(window?.isMiniaturized ?? true)
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
