import SwiftUI
import ServiceManagement
import PlazaCore

struct PreferencesView: View {
    @ObservedObject var model: PlazaModel
    let fillsOverlay: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedCategory: SettingsCategory?
    @ObservedObject private var ffl=FFLResources.shared
    @ObservedObject private var bodies=PlazaBodyResources.shared
    @ObservedObject private var music: PlazaMusicLibrary
    @ObservedObject private var audio: PlazaAudio
    @State private var previewError: String?
    init(model: PlazaModel, fillsOverlay: Bool = false, initialCategory: SettingsCategory? = nil) {
        self.model = model
        self.fillsOverlay = fillsOverlay
        self._selectedCategory = State(initialValue: initialCategory ?? ((model.recoveryRequired || model.document.preferences.safeMode) ? .system : nil))
        self.music = model.music
        self.audio = model.audio
    }
    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            if let selectedCategory {
                categoryHeading(selectedCategory)
                categoryControls
            } else {
                categoryMenu
            }
            settingsFooter
        }
        .foregroundStyle(PlazaStyle.ink)
        .background(SettingsBackground())
        .preferredColorScheme(.light)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedCategory)
        .frame(width: fillsOverlay ? nil : 640, height: fillsOverlay ? nil : 790)
        .frame(maxWidth: fillsOverlay ? .infinity : nil, maxHeight: fillsOverlay ? .infinity : nil)
        .onAppear { model.updateAudio() }
        .onDisappear { audio.stopPreview(); music.discardSelections() }
        .onChange(of: selectedCategory) { old, _ in
            if old == .sound { audio.stopPreview(); music.discardSelections(); previewError = nil }
        }
        .onChange(of: model.sessionActive) { _,_ in model.updateAudio() }
        .onChange(of: model.windowVisible) { _,_ in model.updateAudio() }
        .onChange(of: model.document.preferences.safeMode) { _,_ in model.updateAudio() }
        .onChange(of: model.document.preferences.settingsMusicVolume) { _,_ in model.updateAudio() }
        .onChange(of: model.document.preferences.writingMusicVolume) { _,_ in model.updateAudio() }
        .onChange(of: model.document.preferences.miiverseMusicVolume) { _,_ in model.updateAudio() }
    }
    private var settingsHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "wrench.fill").font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white).frame(width: 54, height: 54)
                .background(LinearGradient(colors: [Color.orange.opacity(0.75), .orange], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 15))
                .shadow(color: .orange.opacity(0.18), radius: 4, y: 3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("System Settings").font(.system(size: 27, weight: .medium, design: .rounded))
                Text(selectedCategory == nil ? "Choose a category." : "Make the plaza yours.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Ver. \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            Button { model.returnToPlaza() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34).background(.white.opacity(0.8), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Close Settings")
        }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
            .background(.white.opacity(0.65))
    }

    private var categoryMenu: some View {
        GeometryReader { proxy in
            let tileHeight = max(80, min(154, (proxy.size.height - 84) / 3))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(SettingsCategory.allCases) { category in
                        SettingsCategoryTile(category: category, height: tileHeight) { selectedCategory = category }
                    }
                }.padding(26)
            }.scrollIndicators(.hidden)
        }
    }

    private func categoryHeading(_ category: SettingsCategory) -> some View {
        HStack(spacing: 16) {
            Image(systemName: category.symbol).symbolRenderingMode(.hierarchical)
                .font(.system(size: 37, weight: .medium)).foregroundStyle(category.color)
                .frame(width: 66, height: 66).background(.white, in: RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(category.title).font(.system(size: 23, weight: .medium, design: .rounded))
                Text(category.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.horizontal, 26).padding(.vertical, 16)
    }

    private var settingsFooter: some View {
        HStack(spacing: 16) {
            Button {
                if selectedCategory == nil { model.returnToPlaza() }
                else { selectedCategory = nil }
            } label: {
                Label(selectedCategory == nil ? "Back to Plaza" : "Categories", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient(colors: [.white, Color.white.opacity(0.65)], startPoint: .top, endPoint: .bottom), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 3)
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            if selectedCategory != nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(SettingsCategory.allCases) { category in
                            Button { selectedCategory = category } label: {
                                Image(systemName: category.symbol).font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(category.color).frame(width: 34, height: 36)
                                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selectedCategory == category ? Color.orange : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).help(category.title)
                                .accessibilityLabel("\(category.title) settings")
                                .accessibilityValue(selectedCategory == category ? "Selected" : "")
                        }
                    }
                }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Select an icon to change settings").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 26).padding(.vertical, 18)
            .background(.white.opacity(0.55))
    }

    private var categoryControls: some View {
            Form {
                if selectedCategory == .updates { UpdateSettingsView() }
                if selectedCategory == .apps {
                    Section("Home screen apps") {
                        Toggle("Rotate home screen at startup", isOn: Binding(get: { model.rotatingHomeEnabled }, set: { enabled in
                            model.mutate { $0.preferences.rotatingHomeScreen = enabled }
                        }))
                        Text("Mix recently launched apps with games your friends are currently playing on Discord, when installed on this Mac. A new mix appears each time Mac Plaza starts; the layout stays steady while you use it. Turn this off to restore your pinned apps and their order.").font(.caption).foregroundStyle(.secondary)
                        if model.rotatingHomeEnabled {
                            Button(model.preparingRotatingHome ? "Finding installed apps…" : "Shuffle Home Screen Now") { model.prepareRotatingHome() }
                                .disabled(model.preparingRotatingHome)
                            Text("Recent launches are remembered locally while rotation is on. The first mix also uses currently running apps. Discord games need visible game activity; unavailable or uninstalled games are skipped. Empty slots use your installed pinned apps.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button { model.beginChangingApps() } label: { Label(model.rotatingHomeEnabled ? "Edit Pinned Apps" : "Change Apps", systemImage: "square.grid.2x2") }
                        Button { model.pickSteamGame() } label: { Label("Add Steam Game", systemImage: "gamecontroller") }
                        Text("Add installed apps, drag icons to change their positions, or click an app to replace or remove its shortcut. Changes save automatically on this Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if selectedCategory == .friends {
                    Section("Discord & Plaza friends") {
                        Text("Link Discord to see your friends’ Miis and availability automatically.").font(.caption).foregroundStyle(.secondary)
                        Button("Discord & Friends…") { model.sheet = .social }
                    }
                }
                if selectedCategory == .display {
                    Section("Desktop wallpaper") {
                        Toggle("Use Mac Plaza as wallpaper", isOn: Binding(get: { model.wallpaperEnabled }, set: { enabled in
                            if enabled { model.desktop.enable() } else { model.desktop.disable() }
                        })).disabled(!model.loaded)
                        Text("Click buttons, app icons and characters directly on the wallpaper. Escape restores Finder’s desktop icons; choose Interact with Plaza in the menu bar to resume. Music mutes when another app plays audio, uses the microphone, goes full screen, or covers most of the plaza. Wallpaper mode is remembered on this Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if selectedCategory == .sound {
                    Section("Music") {
                        Toggle("Play music", isOn: Binding(get: { model.document.preferences.ambientSound ?? true }, set: { value in model.mutate { $0.preferences.ambientSound = value } }))
                        if let reason = model.automaticMusicMuteReason {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                        musicControls(.plaza, title: "Plaza", volume: \.musicVolume, defaultVolume: 0.12)
                        musicControls(.maker, title: "Mii Maker", volume: \.makerMusicVolume, defaultVolume: 0.10)
                        musicControls(.friends, title: "Friends", volume: \.friendsMusicVolume, defaultVolume: 0.10)
                        musicControls(.settings, title: "Settings", volume: \.settingsMusicVolume, defaultVolume: 0.10)
                        musicControls(.writing, title: "Writing Notes", volume: \.writingMusicVolume, defaultVolume: 0.10)
                        musicControls(.miiverse, title: "Miiverse", volume: \.miiverseMusicVolume, defaultVolume: 0.10)
                        Text("Choose an audio file up to 256 MB, preview it, then select Use Music to apply it. Plaza, Mii Maker, Friends, Settings and note-writing music crossfade when you open or close each menu. The plaza theme resumes where it paused when you return. Music yields to other apps’ audio and calls, and to windows covering most of the plaza. It fades back in once the plaza is available and other audio has stopped. Some apps keep audio active briefly after pausing. Your saved tracks loop and stay on this Mac.").font(.caption).foregroundStyle(.secondary)
                        if let previewError { Text(previewError).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                        if let message = music.message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
                if selectedCategory == .motion {
                    Section("Motion & attention") {
                        Toggle("Pause character motion", isOn: preference(\.pauseMotion))
                        Toggle("Larger text", isOn: preferenceOptional(\.largerText))
                        Toggle("Pause journal bubble cycling", isOn: preference(\.pausePosts))
                        Toggle("Private presentation — hide plaza bubbles", isOn: preference(\.privatePresentation))
                        Stepper("Characters in the plaza: \(model.document.preferences.population)", value: Binding(get: { model.document.preferences.population }, set: { number in model.mutate { $0.preferences.population = number }; model.rebuildScene() }), in: PlazaCore.Preferences.populationRange, step: 10)
                        Button("Fill the plaza") {
                            model.mutate { $0.preferences.population = PlazaCore.Preferences.defaultPopulation }
                            model.rebuildScene()
                        }.help("Gather 160 Miis around your app icons.")
                        Text("This is the total crowd, including your Miis and friends. The population stays the same in Low Power Mode. System Reduce Motion is respected. Rendering pauses when the plaza is hidden, covered, or the Mac sleeps.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if selectedCategory == .appearance {
                    Section("Wii U Mii renderer") {
                        Text(ffl.message).font(.caption).textSelection(.enabled)
                        HStack {
                            Button(ffl.installed ? "Replace FFL Resource…":"Import FFLResHigh.dat…") {ffl.importResource()}.disabled(ffl.importing)
                            if ffl.installed {Button("Use Built-in Characters") {ffl.remove()}}
                            if ffl.importing {ProgressView().controlSize(.small)}
                        }
                        Text("Import your Wii U FFLResHigh.dat for original faces and hairstyles. The resource, FFL library and Wii U shader run on this Mac. No renderer service, downloads or uploads are used. Resources stay separate from plaza exports.").font(.caption).foregroundStyle(.secondary)
                        Button("Renderer Credits & Licenses") {NSWorkspace.shared.open(FFLSurface.assetRoot.appendingPathComponent("NOTICES.txt"))}
                        Text("Wii U file: sys/title/0005001b/10056000/content/FFLResHigh.dat").font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                    }
                }
                if selectedCategory == .appearance {
                    Section("Original plaza bodies & animations") {
                        Text(bodies.message).font(.caption).textSelection(.enabled)
                        HStack {
                            Button(bodies.installed ? "Replace Men2.pack…":"Import Men2.pack…") {bodies.importResource()}.disabled(bodies.importing || !ffl.installed)
                            if bodies.installed {Button("Use Authored Motion") {bodies.remove()}}
                            if bodies.importing {ProgressView().controlSize(.small)}
                        }
                        Text("The original male/female body meshes, body atlas and skeletal curves run locally with your FFL heads. Import reads data only; no Wii U code is executed. Menu assets stay separate from plaza exports.").font(.caption).foregroundStyle(.secondary)
                        Text("Wii U menu: content/Common/Package/Men2.pack").font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                    }
                }
                if selectedCategory == .display {
                    Section("Startup") {
                        Toggle("Start Mac Plaza as wallpaper at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                        Button("Open macOS Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        Text("Starts automatically as an interactive wallpaper with your saved music settings. Keep the app in this location. macOS may require approval in Login Items. Safe mode and recovery still open the ordinary window.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if selectedCategory == .data {
                    Section("Your data") {
                        HStack { Button("Export Plaza…") { model.exportPlaza() }; Button("Import Plaza…") { model.importPlaza() }; Button("Restore Backup") { model.recoverBackup() } }
                        Text("Exports contain characters, notes, drawings and shortcut labels. Installed app paths and bookmarks stay on this Mac. Import replaces the plaza; reconnect app shortcuts with Locate App.").font(.caption).foregroundStyle(.secondary)
                        Button("Show Data Folder") { NSWorkspace.shared.open(model.storage.url.deletingLastPathComponent()) }
                    }
                }
                if selectedCategory == .system {
                    Section("Testing & diagnostics") {
                        HStack {
                            Button("Export Diagnostics…") { model.exportDiagnostics() }
                                .disabled(model.diagnosticsExporting)
                            if model.diagnosticsExportURL != nil {
                                Button("Email Diagnostics…") { model.emailDiagnostics() }
                                    .disabled(model.diagnosticsExporting)
                            }
                            if model.diagnosticsExporting { ProgressView().controlSize(.small); Text("Collecting reports…").font(.caption) }
                        }
                        Text("Save a ZIP with recent Mac Plaza crash reports, build details and an optional description of what happened. Reports may contain file paths and system information. Your saved plaza and Discord credentials are excluded; nothing is uploaded.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text("Send reports to:").font(.caption)
                            Link(PlazaDiagnostics.supportEmail, destination: URL(string: "mailto:" + PlazaDiagnostics.supportEmail)!)
                                .font(.caption)
                        }
                        if let message = model.diagnosticsExportMessage {
                            Text(message).font(.caption).textSelection(.enabled)
                        }
                    }
                    Section("Recovery & build") {
                        Toggle("Safe mode — disable 3D, custom icons, music & bubbles", isOn: preference(\.safeMode))
                        Text("Mac Plaza \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Private friend test\nYour local plaza stays on this Mac. Optional sharing publishes your chosen Mii, note and enabled activity to the Discord friends you authorize.").font(.caption).foregroundStyle(.secondary)
                        Text("This local build is ad-hoc signed. Developer ID signing, notarization, full VoiceOver review and hardware sleep/battery testing are release work.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            .id(selectedCategory)
            .onChange(of:ffl.revision) { _,_ in model.rebuildScene() }
            .onChange(of:bodies.revision) { _,_ in model.rebuildScene() }
    }
    private func musicControls(_ track: PlazaAudio.Track, title: String, volume key: WritableKeyPath<Preferences, Double?>, defaultVolume: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(music.title(for: track)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(music.title(for: track))
                }
                Spacer()
                Button("Import Music…") { audio.stopPreview(); previewError = nil; music.choose(for: track) }.accessibilityLabel("Import \(title) music")
                if music.recordings[track.rawValue] != nil {
                    Button("Use Default") { audio.stopPreview(); music.discardSelection(for: track); music.restoreDefault(for: track) }.accessibilityLabel("Use default \(title) music")
                }
            }
            if let selection = music.selections[track.rawValue] {
                Text("Selected: \(selection.name)").font(.caption).lineLimit(2).textSelection(.enabled)
            }
            HStack {
                Button {
                    previewError = nil
                    if audio.previewTrack == track { audio.stopPreview() }
                    else if let url = music.previewURL(for: track) {
                        do { try audio.preview(url, track: track, volume: model.document.preferences[keyPath: key] ?? defaultVolume) }
                        catch { previewError = "Could not preview music: \(error.localizedDescription)" }
                    }
                } label: {
                    Label(audio.previewTrack == track ? "Stop" : "Preview", systemImage: audio.previewTrack == track ? "stop.fill" : "play.fill")
                }.accessibilityLabel("\(audio.previewTrack == track ? "Stop" : "Preview") \(title) music")
                    .disabled(model.document.preferences.safeMode || model.automaticMusicMuteReason != nil || music.previewURL(for: track) == nil)
                if music.selections[track.rawValue] != nil {
                    Button("Use Music") { audio.stopPreview(); music.applySelection(for: track) }
                        .buttonStyle(.borderedProminent).accessibilityLabel("Use selected \(title) music")
                    Button("Cancel") { audio.stopPreview(); music.discardSelection(for: track) }
                        .accessibilityLabel("Cancel selected \(title) music")
                }
                Spacer()
                if audio.previewTrack == track { Text("Previewing…").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Image(systemName: "speaker.wave.1")
                Slider(value: Binding(get: { model.document.preferences[keyPath: key] ?? defaultVolume }, set: { value in
                    model.mutate { $0.preferences[keyPath: key] = value }
                    if audio.previewTrack == track { audio.setPreviewVolume(value) }
                }), in: 0...0.35)
                    .accessibilityLabel("\(title) music volume")
                Text("\(Int((model.document.preferences[keyPath: key] ?? defaultVolume) * 100))%").monospacedDigit().frame(width: 34)
            }
        }.padding(.vertical, 4)
    }
    private func preferenceOptional(_ key: WritableKeyPath<Preferences, Bool?>) -> Binding<Bool> {
        Binding(get: { model.document.preferences[keyPath:key] ?? false }, set: { value in model.mutate { $0.preferences[keyPath:key]=value } })
    }
    private func preference(_ key: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(get: { model.document.preferences[keyPath: key] }, set: { value in model.mutate { $0.preferences[keyPath: key] = value } })
    }
}

struct AppDetailsView: View {
    @ObservedObject var model: PlazaModel
    let appID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    private var app: AppIsland? { model.topicApps.first { $0.id == appID } }
    private var isPinned: Bool { model.document.apps.contains { $0.id == appID } }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "An island of your own", subtitle: "A shortcut to an installed Mac app or Steam game.", backToPlaza: model.returnToPlaza) { model.returnToPlaza() }
            if let app {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 18) {
                        Image(nsImage: model.icon(app)).resizable().frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Plaza label", text: $label).textFieldStyle(.roundedBorder).disabled(!isPinned)
                            Text(model.resolvedURL(app) == nil ? "Unavailable. Locate the app to reconnect this shortcut." : "Ready to open").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Bundle identity", value: app.bundleID).font(.caption).textSelection(.enabled)
                    if let url = model.resolvedURL(app) { Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3) }
                    if isPinned { HStack {
                        Button(model.resolvedURL(app) == nil ? "Locate App…" : "Change App…") { model.pickApp(replacing: app) }
                            .help("Choose the app for this shortcut. Its position, label and custom icon are kept.")
                        Button("Steam Game…") { model.pickSteamGame(replacing: app) }
                    }
                    HStack {
                        Button("Custom Icon…") { model.setCustomIcon(app) }
                        if app.customIcon != nil { Button("Use App Icon") { model.setCustomIcon(app, reset:true) } }
                        Button("Move Earlier") { model.move(app.id, delta: -1) }
                        Button("Move Later") { model.move(app.id, delta: 1) }
                    } } else {
                        Text("This app is part of your rotating home screen. Pin it to your saved layout to customize its label or icon.").font(.callout).foregroundStyle(.secondary)
                        Button("Pin to Saved Layout") { model.pinHomeApp(app) }.disabled(model.resolvedURL(app) == nil)
                    }
                    HStack {
                        if isPinned { Button("Remove Shortcut", role: .destructive) { model.removeApp(app); dismiss() } }
                        Spacer()
                        Button("Open") { model.launch(app) }
                        if isPinned { Button("Save Label") {
                            let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
                            model.rememberLayout()
                            model.mutate { doc in if let i = doc.apps.firstIndex(where: { $0.id == appID }) { doc.apps[i].label = value } }
                            dismiss()
                        }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal).keyboardShortcut(.defaultAction).disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label.count > 60) }
                    }
                }.padding(24)
            }
        }.frame(width: 560).onAppear { label = app?.label ?? "" }
    }
}
