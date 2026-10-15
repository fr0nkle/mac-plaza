import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
import PlazaCore

@MainActor
final class PlazaModel: ObservableObject {
    @Published var document = PlazaDocument()
    @Published var loaded = false
    @Published var journalRevision = 0
    @Published var recoveryRequired = false
    @Published var resourcePackBusy = false
    @Published var resourcePackMessage: String?
    @Published var resourcePackBackup: URL?
    @Published var diagnosticsExporting = false
    @Published var diagnosticsExportMessage: String?
    @Published var diagnosticsDescriptionDraft = ""
    @Published var diagnosticsExportURL: URL?
    @Published private(set) var previousSessionInterrupted = false
    @Published var diagnosticsRecoveryOfferPending = false
    var diagnosticsRecoveryAlert: NSAlert?
    @Published var error: String? { didSet {
        if error != nil { desktop.presentCompanionIfNeeded() }
        else { offerDiagnosticsAfterInterruptedSession() }
    } }
    @Published var status = "Your own little corner of the Mac."
    @Published var launching: Set<UUID> = []
    @Published var search = ""
    @Published var listMode = false
    @Published var editing = false
    @Published var page = 0
    @Published var rotatingApps: [AppIsland] = []
    @Published var preparingRotatingHome = false
    @Published var rotationReady = false
    let recentApps: RecentAppHistory
    let observesSystemAppLaunches: Bool
    var installedRotationApps: [AppIsland] = []
    var rotationScanTask: Task<Void, Never>?
    var rotationNeedsRefresh = false
    var rotationAwaitingFriends = true
    @Published var sheet: PlazaSheet? {
        didSet {
            if oldValue?.id == "characters", sheet?.id != "characters" { makerEditorVisible = false }
            if sheet?.id == "miiverse" {
                desktop.dismissCompanionIfNeeded()
                miiverseWindow.show()
            } else {
                if oldValue?.id == "miiverse" { miiverseWindow.close() }
                if sheet != nil { desktop.presentCompanionIfNeeded() }
                else { desktop.dismissCompanionIfNeeded() }
            }
            updateAudio()
            if sheet == nil { offerDiagnosticsAfterInterruptedSession() }
        }
    }
    @Published var previewAppID: UUID?
    @Published var makerEditorVisible = false
    @Published private(set) var writingNoteDepth = 0
    @Published var sessionActive = true
    @Published var miiverseVisible = false { didSet { if oldValue != miiverseVisible { updateAudio() } } }
    @Published var windowVisible = true
    @Published var wallpaperEnabled = false
    @Published var desktopInteractive = false
    @Published var desktopVisible = false
    @Published var desktopMenuVisible = false
    @Published var menuFullScreen = false
    @Published var otherAppFullScreen = false {
        didSet { if oldValue != otherAppFullScreen { updateAudio() } }
    }
    @Published var otherAppCoversPlaza = false {
        didSet { if oldValue != otherAppCoversPlaza { updateAudio() } }
    }
    @Published var otherAudioActive = false {
        didSet {
            if oldValue != otherAudioActive {
                if otherAudioActive { audio.releaseForAudioInterruption() }
                updateAudio()
            }
        }
    }
    @Published var desktopInsets = EdgeInsets()
    lazy var desktop = DesktopPlazaController(model: self)
    lazy var miiverseWindow = MiiverseWindowController(model: self, frameAutosaveName: observesSystemAppLaunches ? MiiverseWindowController.frameName : nil)
    @Published var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var bubbleSelections = [0,1,2]
    @Published private(set) var postBubbleCount = 1
    @Published private(set) var postPresentation = PlazaPostCadence.Presentation.quiet
    private var postCadence = PlazaPostCadence()
    private var nextJournalPost = 0
    @Published var hoveredBubble = false
    var heldBubbles: Set<Int> = []
    private var draftTask: Task<Void, Never>?
    var selectedNoteID: UUID?
    let scene = PlazaScene(size: CGSize(width: 1200, height: 720))
    let audio=PlazaAudio()
    let music: PlazaMusicLibrary
    let social: SocialController
    let storage: DocumentStorage
    let birthdayReceipt: BirthdayCelebrationReceipt
    let birthdayCelebration = BirthdayCelebrationController()
    private var revision = 0
    private var undoLayouts: [[AppIsland]] = []
    private var iconCache: [String: NSImage] = [:]
    private var observations: [NSObjectProtocol] = []
    private var bubbleTimer: Timer?
    private var lastNoteExpiryCheck: TimeInterval = 0
    private var fullScreenAudioMonitor: FullScreenAudioMonitor?
    private var otherAudioMonitor: OtherAudioMonitor?
    var window: NSWindow?
    let demo = CommandLine.arguments.contains("--demo")

    var renderVisible: Bool { wallpaperEnabled ? desktopVisible : windowVisible }
    var isMoving: Bool {
        loaded && sessionActive && renderVisible && !listMode &&
        (sheet == nil || sheet?.id == "miiverse" || (sheet?.isFloatingMenu == true && !menuFullScreen)) && !document.preferences.pauseMotion &&
        !document.preferences.safeMode && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    var hasAlternateMiiverseMusic: Bool { music.url(for: .miiverseAlternate) != nil || PlazaAudio.soundtrackURL(for: .miiverseAlternate) != nil }
    var miiverseMusicTrack: PlazaAudio.Track {
        document.preferences.miiverseAlternateTheme == true && hasAlternateMiiverseMusic ? .miiverseAlternate : .miiverse
    }
    var musicTrack: PlazaAudio.Track {
        if writingNoteDepth > 0 || sheet?.id == "compose" { return .writing }
        if sheet?.id == "preferences" { return .settings }
        if sheet?.id == "friends" { return .friends }
        if sheet?.id == "miiverse" { return miiverseMusicTrack }
        return sheet?.id == "characters" || makerEditorVisible ? .maker : .plaza
    }
    var musicVolume: Double {
        switch musicTrack {
        case .plaza: return document.preferences.musicVolume ?? 0.12
        case .maker: return document.preferences.makerMusicVolume ?? 0.10
        case .friends: return document.preferences.friendsMusicVolume ?? 0.10
        case .settings: return document.preferences.settingsMusicVolume ?? 0.10
        case .writing: return document.preferences.writingMusicVolume ?? 0.10
        case .miiverse, .miiverseAlternate: return document.preferences.miiverseMusicVolume ?? 0.10
        }
    }
    var automaticMusicMuteReason: String? {
        if otherAudioActive { return "Music muted while another app is playing audio or using the microphone" }
        if otherAppFullScreen { return "Music muted for full-screen app" }
        if otherAppCoversPlaza { return "Music muted while another app covers the plaza" }
        return nil
    }
    var audioEligible: Bool {
        guard loaded, sessionActive, automaticMusicMuteReason == nil, !document.preferences.pauseMotion, !document.preferences.safeMode else { return false }
        if musicTrack != .plaza { return windowVisible || desktopMenuVisible || miiverseVisible }
        // Small windows and hidden companion controls may keep music playing;
        // the window monitor separately detects a blocked plaza.
        return !listMode && (wallpaperEnabled || windowVisible)
    }
    func beginWritingNote() { writingNoteDepth += 1; updateAudio() }
    func endWritingNote() { writingNoteDepth = max(0, writingNoteDepth - 1); updateAudio() }
    func updateAudio() {
        updateUISounds()
        let volume = musicVolume
        audio.update(enabled: (document.preferences.ambientSound ?? true) && audioEligible, volume: volume, track: musicTrack, customURL: music.url(for: musicTrack), allowPreview: sessionActive && automaticMusicMuteReason == nil && (windowVisible || desktopMenuVisible || miiverseVisible) && !document.preferences.safeMode)
    }
    func updateUISounds() {
        guard observesSystemAppLaunches else { return }
        PlazaUISounds.shared.configure(enabled: sessionActive && !document.preferences.safeMode && document.preferences.uiSoundEffects != false,
                                       volume: document.preferences.uiSoundVolume ?? 0.18)
    }
    var filteredApps: [AppIsland] {
        homeApps.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
    }
    var visibleApps: [AppIsland] { Array(filteredApps.dropFirst(page * 12).prefix(12)) }
    var pageCount: Int { max(1, (filteredApps.count + 11) / 12) }
    var receivedNotes: [SharedJournalNote] {
        guard social.hasSession else { return [] }
        return social.visibleSharedJournal.filter { !NoteRetention.isExpired(Date(timeIntervalSince1970: $0.created)) && $0.ownerID != social.account?.id && ($0.topic == nil || $0.topic?.match(in: topicApps) != nil) }
    }
    private var currentSharedNotes: [SharedJournalNote] {
        social.hasSession ? social.visibleSharedJournal.filter { !NoteRetention.isExpired(Date(timeIntervalSince1970: $0.created)) } : []
    }
    var miiverseCatalog: MiiverseCatalog {
        MiiverseCatalog(notes: document.notes, apps: topicApps,
            shared: currentSharedNotes, accountID: social.account?.id, accountDisplayName: social.account?.displayName)
    }
    func journalNote(_ id: UUID) -> LocalNote? {
        document.notes.first { $0.id == id && !NoteRetention.isExpired($0.created) } ?? currentSharedNotes.first { $0.id == id }?.localNote(apps: topicApps)
    }
    var homeSharedNotes: [SharedJournalNote] {
        receivedNotes.filter { $0.topic == nil || $0.topic?.match(in: visibleApps) != nil }
    }
    var allJournalNotes: [LocalNote] {
        (document.notes + receivedNotes.map { $0.localNote(apps: topicApps) }).sorted { $0.created > $1.created }
    }
    func notes(for app: AppIsland) -> [LocalNote] {
        let own = document.notes.filter { note in
            guard let id = note.appID else { return false }
            if id == app.id { return true }
            return topicApps.first { $0.id == id }.map { SharedNoteTopic($0).match(in: [app]) != nil } ?? false
        }
        let shared = receivedNotes.filter { $0.topic?.match(in: [app]) != nil }.map { $0.localNote(apps: [app]) }
        return (own + shared).sorted { $0.created > $1.created }
    }
    func sharedThread(for note: LocalNote) -> SharedJournalNote? {
        guard note.shared == true, social.hasSession else { return nil }
        return social.visibleSharedJournal.first {
            isOwnNote(note) ? ($0.ownerID == social.account?.id && $0.sourceID == note.id) : $0.id == note.id
        }
    }
    func isOwnNote(_ note: LocalNote) -> Bool { document.notes.contains { $0.id == note.id } }
    func noteAvatar(_ note: LocalNote) -> Avatar {
        if note.shared == true {
            if isOwnNote(note) { return document.primaryAvatar }
            if let shared = social.visibleSharedJournal.first(where: { $0.id == note.id }) { return shared.author }
        }
        return document.avatars.first { $0.id == note.authorID } ?? Avatar(name: note.author)
    }
    func noteDisplayName(_ note: LocalNote) -> String {
        guard note.shared == true else { return note.author }
        if isOwnNote(note) { return social.account?.displayName ?? note.author }
        return social.visibleSharedJournal.first { $0.id == note.id }?.publicDisplayName ?? note.author
    }
    func updateSharedJournal() {
        guard loaded, !recoveryRequired else { return }
        social.activityPreviewsAllowed = !document.preferences.privatePresentation
        social.setJournal(notes: document.notes, apps: topicApps, primary: document.primaryAvatar)
    }

    var visibleNotes: [LocalNote] {
        allJournalNotes.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || noteDisplayName($0).localizedCaseInsensitiveContains(search) || $0.drawingDescription.localizedCaseInsensitiveContains(search) }
    }

    init(directory: URL? = nil) {
        observesSystemAppLaunches = directory == nil && !CommandLine.arguments.contains("--demo")
        social = SocialController(isolated: directory != nil || CommandLine.arguments.contains("--demo"))
        let base = directory ?? PlazaDataLocation.root
        birthdayReceipt = BirthdayCelebrationReceipt(url: base.appendingPathComponent("birthday-celebration.json"))
        recentApps = RecentAppHistory(url: base.appendingPathComponent("recent-apps.json"))
        storage = DocumentStorage(url: base.appendingPathComponent("plaza.json"))
        music = PlazaMusicLibrary(directory: base.appendingPathComponent("Music"))
        music.onChange = { [weak self] in self?.updateAudio() }
        scene.onArrivalCue = { [weak self] cue in
            guard let self,self.isMoving,self.audioEligible,self.document.preferences.ambientSound ?? true else{return}
            self.audio.playArrivalEffect(cue,volume:self.document.preferences.musicVolume ?? 0.12)
        }
        scene.onArrivalStopped = { [weak self] in self?.audio.stopArrivalEffects() }
        social.onActivityChanged = { [weak self] in self?.journalRevision &+= 1 }
        social.onActivitySelected = { [weak self] activity in
            guard let self else { return }
            let id = activity.sourceID ?? self.social.sharedJournal.first { $0.id == activity.noteID }?.sourceID
            self.openMiiverse(note: id)
        }
        social.onRosterChanged = { [weak self] in self?.journalRevision &+= 1; self?.refreshHomeForFriendActivity(); self?.rebuildScene() }
        observeLifecycle()
        if directory == nil {
            fullScreenAudioMonitor = FullScreenAudioMonitor(plazaScreen: { [weak self] in
                guard let self else { return nil }
                return self.wallpaperEnabled ? DesktopPlazaController.targetScreen : self.window?.screen ?? DesktopPlazaController.targetScreen
            }) { [weak self] state in
                self?.otherAppCoversPlaza = state.coversPlaza
                self?.otherAppFullScreen = state.fullScreen
            }
            otherAudioMonitor = OtherAudioMonitor { [weak self] active in
                self?.otherAudioActive = active
            }
        }
        var lastPostTick = ProcessInfo.processInfo.systemUptime
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = min(1, max(0, now - lastPostTick))
            lastPostTick = now
            Task { @MainActor in
                self?.advanceBubblePresentation(by: elapsed)
                self?.applyPendingHomeRotation()
                self?.checkBirthday()
                if let self, now - self.lastNoteExpiryCheck >= 60 {
                    self.lastNoteExpiryCheck = now
                    self.expireNotes()
                }
            }
        }
        Task {
            do {
                if let saved = try await storage.load() { document = saved }
                else { seed(); await flush() }
            } catch {
                recoveryRequired = true
                self.error = "The saved plaza could not be read. The original file has been preserved. Restore its backup or import an export from Preferences.\n\n\(error.localizedDescription)"
            }
            do {
                previousSessionInterrupted = try await storage.beginSession()
                diagnosticsRecoveryOfferPending = previousSessionInterrupted
                if previousSessionInterrupted {
                    document.preferences.safeMode = true
                    status = "The previous session ended unexpectedly. Safe mode is on; resume in Preferences."
                }
            } catch { self.error = error.localizedDescription }
            loaded = true
            updateUISounds()
            expireNotes()
            if rotatingHomeEnabled { prepareRotatingHome() }
            rebuildScene()
            scene.beginEntrance(enabled: !document.preferences.safeMode && !document.preferences.pauseMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            offerDiagnosticsAfterInterruptedSession()
        }
    }
    @discardableResult
    func mutate(_ action: (inout PlazaDocument) -> Void) -> Bool {
        guard !recoveryRequired else { error = "Restore a backup or import a plaza before making changes."; return false }
        var next = document; action(&next)
        NoteRetention.prune(&next)
        let wasSafe=document.preferences.safeMode, previousAvatars=document.avatars
        let wasRotating = rotatingHomeEnabled
        do { document = try next.validated() }
        catch { self.error = error.localizedDescription; return false }
        if wasSafe != document.preferences.safeMode || previousAvatars != document.avatars { rebuildScene() }
        if wasRotating != rotatingHomeEnabled {
            page = 0; previewAppID = nil
            if rotatingHomeEnabled { editing = false; prepareRotatingHome() }
            else { rotationScanTask?.cancel(); preparingRotatingHome = false; rotationNeedsRefresh = false }
            updateVisibleIslands()
        }
        updateSharedJournal()
        updateUISounds()
        revision += 1
        let snapshot = document, number = revision
        Task { do { try await storage.save(snapshot, revision: number) } catch { self.error = "Could not save the plaza: \(error.localizedDescription)" } }
        return true
    }
    func expireNotes(now: Date = Date()) {
        guard loaded, !recoveryRequired else { return }
        social.expireJournal(now: now)
        if document.notes.contains(where: { NoteRetention.isExpired($0.created, now: now) }) {
            mutate { NoteRetention.prune(&$0, now: now) }
        }
    }
    func flush() async {
        guard !recoveryRequired else { return }
        NoteRetention.prune(&document)
        updateSharedJournal()
        revision += 1
        do { try await storage.save(document, revision: revision) }
        catch { self.error = "Could not save: \(error.localizedDescription)" }
    }
    func rebuildScene() {
        updateUISounds()
        updateSharedJournal()
        social.setLocalMiis(document.avatars)
        updateVisibleIslands()
        let population = document.preferences.safeMode ? 0 : document.preferences.population
        let room = max(0, population - document.avatars.count)
        let plazaFriends = FriendMiiAssignments.plazaFriends(social.friends, capacity: room, retaining: scene.fflCharacters.map(\.id))
        var seen = Set(document.avatars.map(\.id))
        let noteAuthors = homeSharedNotes.compactMap { PlazaSpeechPost.miiverse($0, friends: social.friends)?.speaker }.filter { seen.insert($0.id).inserted }
        // A public-note primary Mii takes priority over another profile appearance.
        var unique = Set(document.avatars.map(\.id))
        let roster = (noteAuthors + plazaFriends.map(\.avatar)).filter { unique.insert($0.id).inserted }
        scene.configure(avatars: document.avatars + roster.prefix(room), population: population, localCount: document.avatars.count, primaryAvatarID: document.primaryAvatar.id)
        updateVisibleIslands()
    }
    @discardableResult
    func saveMii(_ avatar:Avatar) -> Bool {
        let isNew = !document.avatars.contains(where:{$0.id==avatar.id})
        guard mutate({ doc in
            if let index=doc.avatars.firstIndex(where:{$0.id==avatar.id}) {doc.avatars[index]=avatar}
            else {doc.avatars.append(avatar)}
        }) else{return false}
        rebuildScene()
        if isNew {
            desktop.closeMakerForArrival { [weak self] in
                guard let self else{return}
                self.sheet=nil;self.makerEditorVisible=false;self.listMode=false;self.previewAppID=nil
                if self.wallpaperEnabled {self.desktop.interact()}
                self.scene.beginArrival(for:avatar.id,animated:!self.document.preferences.pauseMotion && !self.document.preferences.safeMode && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
        return true
    }
    func updateVisibleIslands() {
        var assignments: [UUID: UUID] = [:]
        for friend in social.friends {
            if let app = FriendActivityMatcher.island(for: friend.activities, apps: visibleApps) {
                assignments[friend.avatar.id] = app
            }
        }
        for note in homeSharedNotes.reversed() {
            if let app = note.topic?.match(in: visibleApps), let speaker = PlazaSpeechPost.miiverse(note, friends: social.friends)?.speaker { assignments[speaker.id] = app.id }
        }
        scene.setGathering(assignments, apps: visibleApps.map(\.id))
    }
    func openCharacter(_ avatar: Avatar) {
        if let note = receivedNotes.first(where: { $0.author.id == avatar.id }) { openMiiverse(note: note.id); return }
        if let friend = social.friends.first(where: { $0.avatar.id == avatar.id }) { sheet = .friend(friend) }
        else { sheet = .profile(avatar) }
    }
    func openMiiverse(note: UUID? = nil) {
        selectedNoteID=note
        if let note { mutate { doc in if let i=doc.notes.firstIndex(where:{$0.id==note}) { doc.notes[i].read=true } } }
        sheet = .miiverse
    }
    private func seed() {
        let candidates = ["/Applications/DaVinci Resolve/DaVinci Resolve.app", "/Applications/Brave Browser.app", "/Applications/Discord.app", "/System/Applications/Music.app", "/System/Applications/Notes.app", "/System/Applications/Messages.app", "/System/Applications/Calendar.app", "/System/Applications/Photos.app"]
        document.apps = candidates.compactMap { try? Self.island(at: URL(fileURLWithPath: $0)) }
        var primary = Avatar(name: "You", outfit: 0); primary.hair = 1
        var second = Avatar(name: "Pip", outfit: 3); second.skin = 3; second.hair = 2; second.glasses = true
        var third = Avatar(name: "Cleo", outfit: 6); third.hair = 4; third.skin = 2
        document.avatars = [primary, second, third]; document.primaryAvatarID = primary.id
    }
    static func island(at url: URL) throws -> AppIsland {
        guard url.isFileURL, url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, bundle.executableURL != nil,
              FileManager.default.fileExists(atPath: url.path)
        else { throw PlazaError.invalid("Choose an installed Mac application (.app).") }
        let label = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var island = AppIsland(label: String(label.prefix(60)), bundleID: identifier, path: url.path, bookmark: bookmark)
        if let game = SteamGames.game(forApplication: url) { island.label = game.name; island.steamAppID = game.id }
        return island
    }
    func resolvedURL(_ app: AppIsland) -> URL? {
        if let bookmark = app.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
               validTarget(url, app: app) { return url }
        }
        if let path = app.path {
            let url = URL(fileURLWithPath: path)
            if validTarget(url, app: app) { return url }
        }
        return nil
    }
    private func validTarget(_ url: URL, app: AppIsland) -> Bool {
        url.pathExtension == "app" && FileManager.default.fileExists(atPath: url.path) && Bundle(url: url)?.bundleIdentifier == app.bundleID
    }
    func icon(_ app: AppIsland) -> NSImage {
        let key=app.id.uuidString+"\(document.preferences.safeMode)"
        if let image = iconCache[key] { return image }
        let custom=document.preferences.safeMode ? nil:app.customIcon.flatMap(NSImage.init(data:))
        let image = custom ?? resolvedURL(app).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Locate application")!
        image.size = NSSize(width: 128, height: 128); iconCache[key] = image
        return image
    }
    func launch(_ app: AppIsland) {
        guard !launching.contains(app.id) else { return }
        guard let url = resolvedURL(app) else {
            if document.apps.contains(where: { $0.id == app.id }) {
                sheet = .app(app); status = "Locate \(app.label) to reconnect this shortcut."
            } else { error = "\(app.label) is no longer installed. Shuffle the home screen in Settings to refresh its apps." }
            return
        }
        // Refresh moved/stale bookmark references only after identity validation.
        if let fresh = try? Self.island(at: url), fresh.path != app.path || fresh.bookmark != app.bookmark {
            mutate { doc in if let i = doc.apps.firstIndex(where: { $0.id == app.id }) { doc.apps[i].path = fresh.path; doc.apps[i].bookmark = fresh.bookmark } }
        }
        let game = SteamGames.game(forApplication: url)
        if let id = app.steamAppID, game?.id != id {
            error = "This Steam game has moved or changed. Use Add Steam Game to reconnect this shortcut."; return
        }
        let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.launching.remove(app.id)
                if let error { self.error = "Could not open \(app.label): \(error.localizedDescription)" }
                else { self.recordRecentLaunch(app); self.status = game == nil ? "\(app.label) opened. Welcome back whenever you like." : "Steam is opening \(app.label)."; if let i=self.visibleApps.firstIndex(where:{$0.id==app.id}) {self.scene.react(to:i)} }
            }
        }
        launching.insert(app.id); status = "Opening \(app.label)…"
        if let game {
            guard let steam = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam") else {
                launching.remove(app.id); error = "Install Steam to launch \(app.label)."; return
            }
            NSWorkspace.shared.open([game.launchURL], withApplicationAt: steam, configuration: NSWorkspace.OpenConfiguration(), completionHandler: completion)
        } else {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: completion)
        }
    }
    func beginChangingApps() {
        sheet = nil
        if wallpaperEnabled && !desktopInteractive { desktop.interact() }
        previewAppID = nil
        listMode = false
        search = ""
        page = 0
        editing = true
        if rotatingHomeEnabled { status = "Editing your pinned layout. Turn off Rotate Home Screen in Settings to use it." }
    }
    func returnToPlaza() {
        sheet = nil
        previewAppID = nil
        listMode = false
        if wallpaperEnabled { desktop.resumeInteraction() }
    }
    func pickApp(replacing old: AppIsland? = nil) {
        guard document.apps.count < 120 || old != nil else { error = "This plaza supports up to 120 apps."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = old == nil
        panel.message = old == nil ? "Choose applications to add to your plaza." : "Choose the application for this shortcut."
        guard panel.runModal() == .OK else { return }
        addApps(panel.urls, replacing: old)
    }
    func pickSteamGame(replacing old: AppIsland? = nil) {
        guard document.apps.count < 120 || old != nil else { error = "This plaza supports up to 120 apps."; return }
        sheet = .steamGames(old)
    }
    func addApps(_ urls: [URL], replacing old: AppIsland? = nil) {
        do {
            let apps = try urls.map { try Self.island(at: $0) }
            rememberLayout()
            mutate { doc in
                for var app in apps {
                    if let old, let i = doc.apps.firstIndex(where: { $0.id == old.id }) {
                        app.id = old.id; app.label = old.label; app.customIcon = old.customIcon; doc.apps[i] = app
                    } else if !doc.apps.contains(where: { $0.bundleID == app.bundleID && $0.path == app.path }), doc.apps.count < 120 { doc.apps.append(app) }
                }
            }
            iconCache.removeAll(); status = "App shortcuts saved."
        } catch { self.error = error.localizedDescription }
    }
    func rememberLayout() { undoLayouts.append(document.apps); if undoLayouts.count > 20 { undoLayouts.removeFirst() } }
    func move(_ id: UUID, delta: Int) {
        guard let index = document.apps.firstIndex(where: { $0.id == id }), document.apps.indices.contains(index + delta) else { return }
        rememberLayout(); mutate { $0.apps.swapAt(index, index + delta) }
    }
    /// Insert at the destination's original slot, shifting the intervening apps.
    /// This also lets a forward drag reach the final slot on a page.
    @discardableResult
    func move(_ id: UUID, to target: UUID) -> Bool {
        guard !recoveryRequired, id != target,
              let from = document.apps.firstIndex(where: { $0.id == id }),
              let to = document.apps.firstIndex(where: { $0.id == target }) else { return false }
        let previous = document.apps
        guard mutate({ doc in
            let item = doc.apps.remove(at: from)
            doc.apps.insert(item, at: to)
        }) else { return false }
        undoLayouts.append(previous)
        if undoLayouts.count > 20 { undoLayouts.removeFirst() }
        return true
    }
    func acceptAppDrop(_ items: [String], onto target: UUID) -> Bool {
        guard editing, items.count == 1, let value = items.first,
              let id = UUID(uuidString: value) else { return false }
        return move(id, to: target)
    }
    func removeApp(_ app: AppIsland) {
        rememberLayout(); mutate { $0.apps.removeAll { $0.id == app.id } }; page = min(page, pageCount - 1)
    }
    func undoLayout() { guard let previous = undoLayouts.popLast() else { return }; mutate { $0.apps = previous }; iconCache.removeAll(); page=min(page,pageCount-1); status="Previous layout restored." }
    func resetLayout() { rememberLayout(); mutate { $0.apps.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending } }; page=0; status="Layout reset to alphabetical order. Undo restores the previous arrangement." }
    func setCustomIcon(_ app: AppIsland, reset: Bool = false) {
        do {
            var data: Data?
            if !reset {
                let panel=NSOpenPanel(); panel.allowedContentTypes=[.png,.jpeg,.tiff]; panel.message="Choose an image for this island."
                guard panel.runModal() == .OK,let url=panel.url else { return }
                guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 10_000_000, let source=NSImage(contentsOf:url), source.size.width>0,source.size.height>0 else { throw PlazaError.invalid("Choose an image smaller than 10 MB.") }
                let image=NSImage(size:NSSize(width:128,height:128)); image.lockFocus(); source.draw(in:NSRect(x:0,y:0,width:128,height:128)); image.unlockFocus()
                guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) else { throw PlazaError.invalid("The icon could not be read.") }; data=png
            }
            rememberLayout(); mutate { doc in if let i=doc.apps.firstIndex(where:{$0.id==app.id}) { doc.apps[i].customIcon=data } }; iconCache.removeAll()
        } catch { self.error=error.localizedDescription }
    }
    func advanceBubblePresentation(by seconds: TimeInterval) {
        guard loaded, renderVisible, sessionActive, sheet == nil, previewAppID == nil,
              !listMode, !editing, search.isEmpty, scene.entranceClock.finished, scene.arrivalClock.avatar == nil,
              !document.preferences.safeMode, !document.preferences.privatePresentation,
              !document.preferences.pausePosts else { return }
        postCadence.advance(by: seconds, held: hoveredBubble)
        let next = postCadence.presentation
        guard next != postPresentation else { return }
        if next == .journal {
            bubbleSelections = (0..<3).map { nextJournalPost + $0 }
            nextJournalPost = (nextJournalPost + 1) % max(1, bubbleNotes.count + 3)
        }
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.35)) {
            postBubbleCount = postCadence.bubbleCount
            postPresentation = next
        }
    }
    func holdBubble(_ index: Int, held: Bool) {
        if held { heldBubbles.insert(index) } else { heldBubbles.remove(index) }
        let anyHeld = !heldBubbles.isEmpty
        if hoveredBubble != anyHeld { hoveredBubble = anyHeld }
    }
    var bubbleNotes: [LocalNote] { visibleNotes.sorted { lhs,rhs in if (lhs.read ?? false) != (rhs.read ?? false) { return !(lhs.read ?? false) }; return lhs.created>rhs.created } }
    func storeDraft(_ draft: NoteDraft?) {
        guard !recoveryRequired else { return }
        let draft = draft?.hasContent == true ? draft : nil
        guard document.draft != draft else { return }
        draftTask?.cancel()
        var next=document; next.draft=draft
        guard (try? next.validated()) != nil else { return }
        document=next; revision+=1; let number=revision,snapshot=next
        draftTask=Task { try? await Task.sleep(for:.milliseconds(400)); guard !Task.isCancelled else { return }; do { try await storage.save(snapshot,revision:number) } catch { self.error=error.localizedDescription } }
    }
    func clearDraft() { draftTask?.cancel(); mutate { $0.draft=nil } }

    func exportPlaza() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "My Plaza.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(document.portable()).write(to: url, options: .atomic); status = "Plaza exported. App references will need reconnecting on import." }
        catch { self.error = error.localizedDescription }
    }
    func importPlaza() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.message = "Import a plaza. The current plaza will be backed up. App shortcuts must be reconnected."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? Int.max) <= 12_000_000 else { throw PlazaError.invalid("Plaza files must be smaller than 12 MB.") }
            let imported = try DocumentStorage.decode(Data(contentsOf: url)).portable()
            // Imported data can never introduce a launchable local path or bookmark.
            recoveryRequired = false; document = imported; NoteRetention.prune(&document); iconCache.removeAll(); page = 0; if rotatingHomeEnabled { prepareRotatingHome() }; rebuildScene()
            Task { await flush() }; status = "Plaza imported. Use Locate App to reconnect shortcuts."
        } catch { self.error = error.localizedDescription }
    }
    func recoverBackup() {
        Task {
            do { document = try await storage.recoverBackup(); NoteRetention.prune(&document); recoveryRequired = false; if rotatingHomeEnabled { prepareRotatingHome() }; rebuildScene(); await flush(); status = "Backup restored." }
            catch { self.error = "Backup could not be restored: \(error.localizedDescription)" }
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && loginEnabled { desktop.enable() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "Login preference could not be changed: \(error.localizedDescription)"; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    private func observeLifecycle() {
        let workspace = NSWorkspace.shared.notificationCenter
        if observesSystemAppLaunches {
            observations.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                Task { @MainActor in
                    guard let self, self.rotatingHomeEnabled, let app, app.activationPolicy == .regular,
                          let url = app.bundleURL, let island = try? Self.island(at: url) else { return }
                    self.recordRecentLaunch(island)
                }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observations.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.sessionActive = false } })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observations.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in guard let self else { return }; self.sessionActive = true
 } })
        }
        observations.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled; self?.rebuildScene() } })
    }
}

enum PlazaSheet: Identifiable {
    case characters, friends, compose(UUID?), miiverse, activity, preferences, social, app(AppIsland), profile(Avatar), friend(SharedMii), steamGames(AppIsland?)
    var isFloatingMenu: Bool { ["characters", "friends", "preferences", "compose", "activity"].contains(id) }
    var id: String {
        switch self { case .steamGames: return "steam-games"; case .friends: return "friends"; case .friend(let friend): return "friend-"+friend.id; case .social: return "social"; case .profile(let avatar): return "profile-"+avatar.id.uuidString; case .characters: return "characters"; case .compose: return "compose"; case .miiverse: return "miiverse"; case .activity: return "activity"; case .preferences: return "preferences"; case .app(let app): return app.id.uuidString }
    }
}
