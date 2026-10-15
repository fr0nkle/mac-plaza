import SwiftUI
import AppKit
import PlazaCore
import UniformTypeIdentifiers

enum PlazaStyle {
    static let ink = Color(red: 0.16, green: 0.24, blue: 0.26)
    static let teal = Color(red: 0.23, green: 0.49, blue: 0.46)
    static let paper = Color(red: 0.96, green: 0.97, blue: 0.95)
}

struct PlazaView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject private var updater = PlazaUpdater.shared
    var desktop = false
    @FocusState private var focusedApp: UUID?
    @State private var plazaZoom: CGFloat = 1
    @State private var plazaOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var content: some View {
        VStack(spacing: 0) {
            if !desktop { header.disabled(model.previewAppID != nil) }
            if model.recoveryRequired {
                Label("Your saved file needs recovery. Open Preferences to restore a backup or import a plaza.", systemImage: "exclamationmark.triangle")
                    .padding(10).frame(maxWidth: .infinity).background(.yellow.opacity(0.18))
            }
            if model.listMode { AppListView(model: model) }
            else { plaza }
            if !desktop { footer }
        }
        .foregroundStyle(PlazaStyle.ink)
        .background(PlazaStyle.paper)
        .frame(minWidth: desktop ? 0 : 1060, minHeight: desktop ? 0 : 720)
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, model.document.preferences.largerText == true ? .accessibility1 : .large)
        .overlay(alignment: .topLeading) {
            if desktop && model.desktopInteractive { desktopControls.padding(16) }
        }
    }
    private var audioContent: some View {
        content
        .onChange(of:model.audioEligible) { _,_ in updateAudio() }
        .onChange(of:model.document.preferences.ambientSound) { _,_ in updateAudio() }
        .onChange(of:model.document.preferences.musicVolume) { _,_ in updateAudio() }
        .onChange(of:model.musicTrack) { _,_ in updateAudio() }
        .onChange(of:model.document.preferences.makerMusicVolume) { _,_ in updateAudio() }
        .onChange(of:model.document.preferences.friendsMusicVolume) { _,_ in updateAudio() }
        .onChange(of:model.document.preferences.settingsMusicVolume) { _,_ in updateAudio() }
        .onChange(of:model.document.preferences.writingMusicVolume) { _,_ in updateAudio() }
        .onChange(of:model.document.preferences.miiverseMusicVolume) { _,_ in updateAudio() }
        .onAppear { updateAudio() }
    }
    var body: some View {
        audioContent
        .onChange(of: reduceMotion) { _, value in if value {model.scene.finishEntrance();model.scene.finishArrival()} }
        .onChange(of: model.document.preferences.pauseMotion) { _, value in if value {model.scene.finishEntrance();model.scene.finishArrival()} }
        .modifier(SocialActivityModifier(model: model))
        .onChange(of: model.editing) { _, _ in model.previewAppID = nil }
        .onChange(of: model.listMode) { _, _ in model.previewAppID = nil }
        .onChange(of: model.page) { _, _ in model.previewAppID = nil }
        .onChange(of: model.search) { _, _ in model.previewAppID = nil }
        .onChange(of: model.sheet?.id) { _, value in if value != nil { model.previewAppID = nil } }
        .onChange(of: model.homeApps) { _, apps in
            if let id = model.previewAppID, !apps.contains(where: { $0.id == id }) { model.previewAppID = nil }
        }
        .onChange(of: model.search) { _, _ in model.page = 0; model.updateVisibleIslands() }
        .onChange(of: model.page) { _, _ in model.updateVisibleIslands() }
        .onChange(of: model.homeApps) { _, _ in model.updateVisibleIslands() }
        .onChange(of: model.loaded) { _, _ in model.updateVisibleIslands() }
    }
    private func updateAudio() { model.updateAudio() }
    private var header: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .center, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill").font(.system(size: 26 + (model.document.preferences.largerText == true ? 2 : 0), weight: .medium)).foregroundStyle(PlazaStyle.teal)
                    Text("Mac Plaza").font(.system(size: 25 + (model.document.preferences.largerText == true ? 2 : 0), weight: .bold, design: .rounded))
                }
                Spacer()
                SocialConnectionBadge(social: model.social) { model.sheet = .social }
                PlazaButton { model.sheet = .preferences } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 17 + (model.document.preferences.largerText == true ? 2 : 0))).padding(7) }.buttonStyle(.plain)
                    .modifier(PlazaUpdateIndicator(available: updater.updateAvailable, label: "Settings"))
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(greeting).font(.system(size: 22 + (model.document.preferences.largerText == true ? 2 : 0), weight: .semibold, design: .rounded))
                    Text("A familiar place to start something.").font(.system(size: 12 + (model.document.preferences.largerText == true ? 2 : 0))).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find an app or note", text: $model.search).textFieldStyle(.plain).frame(width: 155)
                    if !model.search.isEmpty { PlazaButton { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                }.padding(10).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                PlazaButton { model.sheet = .characters } label: {
                    HStack(spacing: 6) {
                        Group { if model.document.preferences.safeMode { Image(nsImage: AvatarArtwork.face(model.document.primaryAvatar)).resizable().scaledToFit() } else { AvatarPortrait(avatar:model.document.primaryAvatar) } }.frame(width:25,height:32)
                        Text("Characters")
                    }
                }.buttonStyle(ToolbarButtonStyle(large:model.document.preferences.largerText == true)).contextMenu { PlazaButton("View Your Profile") { model.sheet = .profile(model.document.primaryAvatar) } }
                PlazaButton { model.pickApp() } label: { Label("Add App", systemImage: "plus") }.buttonStyle(ToolbarButtonStyle(prominent:true,large:model.document.preferences.largerText == true)).keyboardShortcut("n", modifiers: .command)
            }
        }.padding(.horizontal, 30).padding(.top, 20).padding(.bottom, 15)
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let time = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return "\(time), \(model.document.primaryAvatar.name)."
    }
    private var plaza: some View {
      PlazaArrivalPresentation(clock:model.scene.arrivalClock) { arrivalTime in
        GeometryReader { proxy in
            let selected = model.visibleApps.first { $0.id == model.previewAppID }
            let slots = PlazaLayout.slots(for: model.visibleApps.count)
            let selectedSlot = selected.flatMap { app in model.visibleApps.firstIndex { $0.id == app.id } }.map { slots[$0] }
            let focus = selectedSlot.map { PlazaViewport.appFocus(at: $0, size: proxy.size) }
            let normalZoom = focus?.zoom ?? plazaZoom
            let normalOffset = focus?.offset ?? PlazaViewport.offset(plazaOffset, zoom: normalZoom, size: proxy.size)
            let arrivalFocus=arrivalTime.map {PlazaViewport.arrivalFocus(elapsed:$0,zoom:normalZoom,offset:normalOffset,size:proxy.size)}
            let zoom=arrivalFocus?.zoom ?? normalZoom
            let offset=arrivalFocus?.offset ?? normalOffset
            let walkingBounds=PlazaViewport.walkingBounds(size:proxy.size,zoom:plazaZoom,
                offset:PlazaViewport.offset(plazaOffset,zoom:plazaZoom,size:proxy.size),
                insets:desktop ? model.desktopInsets:EdgeInsets())
            ZStack {
              ZStack {
                ForEach(Array(model.visibleApps.enumerated()), id: \.element.id) { index, app in
                    IslandView(model: model, app: app, index: index, tileSize: PlazaLayout.tileSize(in: proxy.size), reduceMotion: reduceMotion) {
                        if model.editing { model.sheet = .app(app) }
                        else { withAnimation(reduceMotion ? nil : .timingCurve(0.22, 0.72, 0.15, 1, duration: 0.9)) { model.previewAppID = app.id } }
                    }
                        .focused($focusedApp, equals: app.id)
                        .onMoveCommand { direction in
                            guard let current = model.visibleApps.firstIndex(where: { $0.id == focusedApp }) else { return }
                            let delta = direction == .left || direction == .up ? -1 : 1
                            let next = (current + delta + model.visibleApps.count) % model.visibleApps.count
                            focusedApp = model.visibleApps[next].id
                        }
                        .modifier(PlazaIslandEntrance(clock:model.scene.entranceClock,slot:slots[index],size:proxy.size))
                        .position(x: slots[index].x * proxy.size.width, y: slots[index].y * proxy.size.height)
                }
                if selected == nil && arrivalTime == nil && !model.document.preferences.privatePresentation && !model.document.preferences.safeMode && model.loaded && !model.editing && model.search.isEmpty {
                    FriendNotesLayer(scene: model.scene, social: model.social, paused: model.document.preferences.pausePosts,
                                     showPosts: model.postPresentation == .friends,
                                     onHoldChanged: { model.holdBubble(1, held: $0) },
                                     journalPosts: model.postPresentation == .quiet ? [] : model.journalPosts(),
                                     maxPosts: model.postBubbleCount,
                                     onSelectJournal: { model.openMiiverse(note: $0) },
                                     largerText: model.document.preferences.largerText == true, islands: Array(slots.prefix(model.visibleApps.count)),
                                     reserved: [],
                                     onSelect: { model.sheet = .friend($0) }).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .modifier(PlazaEntranceReveal(clock:model.scene.entranceClock))
                }
                if model.visibleApps.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: model.search.isEmpty ? "plus.app" : "magnifyingglass").font(.system(size: 35 + (model.document.preferences.largerText == true ? 2 : 0))).foregroundStyle(PlazaStyle.teal)
                        Text(model.search.isEmpty ? "Your plaza starts here." : "No apps found.").font(.title3)
                        PlazaButton("Add an application") { model.pickApp() }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal)
                    }.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
              }
              .scaleEffect(zoom)
              .offset(offset)
              .animation(arrivalTime != nil && !reduceMotion ? .linear(duration:1.0/30):nil,value:arrivalTime)
              .allowsHitTesting(selected == nil && arrivalTime == nil)
              .accessibilityHidden(selected != nil || arrivalTime != nil)
              if selected == nil && arrivalTime == nil {
                  VStack {
                      Spacer()
                      HStack(alignment: .bottom) {
                          PlazaControlSurface {
                              VStack(spacing: 9) {
                                  plazaZoomControls(size: proxy.size)
                                  bugReportButton
                              }
                          }.frame(width: 160, height: 78)
                          Spacer()
                          PlazaControlSurface { PlazaBottomControls(model: model, social: model.social) }
                              .frame(width: 292, height: model.social.activityAlert == nil ? 116 : 216)
                      }
                  }.padding(20).zIndex(1)
              }
              if selected == nil && arrivalTime == nil {
                  VStack {
                      HStack {
                          Spacer()
                          PlazaControlSurface { PlazaHomeControls(model: model) }
                              .frame(width: 374, height: model.editing ? 122 : 70)
                      }
                      Spacer()
                  }.padding(18).zIndex(1)
              }
              if model.editing {
                  VStack {
                      Spacer()
                      Text(model.rotatingHomeEnabled ? "Editing saved pins · Rotation returns when you finish · Turn off rotation in Settings to show these pins" : "Drag apps to reorder · Click an app to replace, rename or remove it · Drop apps from Finder to add")
                          .font(.system(size: 12, weight: .medium))
                          .multilineTextAlignment(.center).padding(12)
                          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                  }.padding(.horizontal, 170).padding(.bottom, 72)
                      .allowsHitTesting(false).zIndex(1)
              }
              if let selected {
                  Color.clear.contentShape(Rectangle()).onTapGesture { closePreview() }.accessibilityHidden(true)
                  AppPreviewView(model: model, app: selected, close: closePreview, maximumHeight: max(240, proxy.size.height - 70))
                      .frame(width: min(360, proxy.size.width * 0.34))
                      .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.46)
                      .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25).delay(reduceMotion ? 0 : 0.38)), removal: .opacity.animation(.easeOut(duration: 0.12))))
                      .zIndex(2)
                  VStack {
                      HStack {
                          PlazaButton(sound: .back, action: closePreview) { Label("Back to plaza", systemImage: "chevron.left") }
                              .keyboardShortcut(.cancelAction).buttonStyle(.plain)
                              .font(.system(size: 13, weight: .semibold)).padding(12)
                              .background(.white.opacity(0.95), in: Capsule())
                          Spacer()
                      }
                      Spacer()
                  }.padding(20).transition(.opacity).zIndex(3)
              }
              if arrivalTime != nil,let avatar=model.scene.arrivalClock.avatar {
                  VStack {
                      Spacer()
                      HStack(spacing:16) {
                          Text("Welcome, \(avatar.name)!").font(.system(size:20,weight:.medium,design:.rounded))
                          PlazaButton("Skip") {model.scene.finishArrival()}.keyboardShortcut(.cancelAction)
                      }.padding(.horizontal,24).padding(.vertical,14)
                          .background(.regularMaterial,in:Capsule())
                  }.padding(.bottom,30).zIndex(4)
              }
            }
            .background(PlazaNavigationInput(enabled: selected == nil && model.sheet == nil && arrivalTime == nil, canPan: !model.editing, zoom: zoom, offset: offset,
                onZoom: { setPlazaZoom($0, size: proxy.size) },
                onPan: { plazaOffset = PlazaViewport.offset($0, zoom: plazaZoom, size: proxy.size) }))
            .clipped()
            // Keep controls in the safe area; floor and walkers continue
            // beneath the wallpaper margins and beyond the camera edges.
            .background {
                ZStack {
                    plazaFloor(size: proxy.size, zoom: zoom, offset: offset, arrivalTime: arrivalTime)
                    if !model.document.preferences.safeMode {
                        SceneView(scene:model.scene,moving:model.isMoving && !reduceMotion,
                                  onSelect:model.openCharacter,renderScale:PlazaScene.renderScale)
                            .frame(width:proxy.size.width*PlazaScene.renderScale,height:proxy.size.height*PlazaScene.renderScale)
                            .scaleEffect(zoom).offset(offset)
                            .animation(arrivalTime != nil && !reduceMotion ? .linear(duration:1.0/30):nil,value:arrivalTime)
                            .allowsHitTesting(selected == nil && arrivalTime == nil).accessibilityHidden(true)
                            .frame(width:proxy.size.width,height:proxy.size.height)
                            .clipShape(PlazaActorClip(unbounded:desktop))
                    }
                }
            }
            .onAppear {model.scene.setWalkingBounds(walkingBounds)}
            .onChange(of:walkingBounds) {_,bounds in model.scene.setWalkingBounds(bounds)}
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard model.editing else { return false }
                for provider in providers {
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        Task { @MainActor in model.addApps([url]) }
                    }
                }
                return true
            }
        }
      }
    }
    @ViewBuilder
    private func plazaFloor(size: CGSize, zoom: CGFloat, offset: CGSize, arrivalTime: Double?) -> some View {
        let horizontalInset = desktop ? model.desktopInsets.leading + model.desktopInsets.trailing : 0
        let verticalInset = desktop ? model.desktopInsets.top + model.desktopInsets.bottom : 0
        let ground = PlazaGround(viewportSize: size)
            .frame(width: (size.width + horizontalInset) * 2, height: (size.height + verticalInset) * 2)
            .scaleEffect(zoom)
            .offset(offset)
            .animation(arrivalTime != nil && !reduceMotion ? .linear(duration: 1.0 / 30) : nil, value: arrivalTime)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        if desktop { ground }
        else { ground.frame(width: size.width, height: size.height).clipped() }
    }
    private func setPlazaZoom(_ value: CGFloat, size: CGSize) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.22,0.61,0.36,1,duration:0.32)) {
            plazaZoom = PlazaViewport.zoom(value)
            plazaOffset = PlazaViewport.offset(plazaOffset, zoom: plazaZoom, size: size)
        }
        if !desktop { model.window?.isMovableByWindowBackground = plazaZoom <= 1 }
    }
    private func plazaZoomControls(size: CGSize) -> some View {
        HStack(spacing: 9) {
            PlazaButton { setPlazaZoom(plazaZoom - 0.15, size: size) } label: {
                Image(systemName: "minus").frame(width: 30, height: 30).contentShape(Rectangle())
            }.disabled(plazaZoom <= PlazaViewport.zoomRange.lowerBound)
                .accessibilityLabel("Zoom out of plaza").help("Zoom out (⌘−)")
                .keyboardShortcut("-", modifiers: .command)
            PlazaButton {
                setPlazaZoom(1, size: size)
                plazaOffset = .zero
            } label: {
                Text("\(Int((plazaZoom * 100).rounded()))%")
                    .monospacedDigit().frame(width: 48, height: 30).contentShape(Rectangle())
            }.accessibilityLabel("Reset plaza zoom to 100 percent")
                .accessibilityValue("\(Int((plazaZoom * 100).rounded())) percent")
                .help("Reset zoom (⌘0). Pinch to zoom; drag to explore when zoomed in.")
                .keyboardShortcut("0", modifiers: .command)
            PlazaButton { setPlazaZoom(plazaZoom + 0.15, size: size) } label: {
                Image(systemName: "plus").frame(width: 30, height: 30).contentShape(Rectangle())
            }.disabled(plazaZoom >= PlazaViewport.zoomRange.upperBound)
                .accessibilityLabel("Zoom into plaza").help("Zoom in (⌘+)")
                .keyboardShortcut("=", modifiers: .command)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(PlazaStyle.ink)
        .buttonStyle(.plain).padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.8)).allowsHitTesting(false))
    }
    private func closePreview() {
        let id = model.previewAppID
        withAnimation(reduceMotion ? nil : .timingCurve(0.22, 0.72, 0.15, 1, duration: 0.7)) { model.previewAppID = nil }
        focusedApp = id
    }
    private var bugReportButton: some View {
        PlazaButton { NSWorkspace.shared.open(BugReport.emailURL()) } label: {
            Label("Report a Bug", systemImage: "ladybug")
        }.font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .help("Email alexanderhosier@squidproductions.org")
    }
    private var desktopControls: some View {
        HStack(spacing: 14) {
            PlazaButton("Return to Desktop · Esc") { model.desktop.returnToDesktop() }
        }.font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
            .padding(12).background(.regularMaterial, in: Capsule())
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(PlazaStyle.ink.opacity(0.07)).frame(height: 1)
            HStack(spacing: 20) {
                PlazaButton { model.openMiiverse() } label: {
                    Label("Miiverse", systemImage: "text.bubble")
                    Text("\(model.document.notes.count)").font(.system(size: 10 + (model.document.preferences.largerText == true ? 2 : 0), weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3).background(PlazaStyle.teal.opacity(0.1), in: Capsule())
                }.overlay(alignment: .topTrailing) {
                    PlazaUnreadActivityBadge(count: model.social.unreadActivityCount).offset(x: 8, y: -8)
                }.accessibilityLabel("Miiverse, \(model.social.unreadActivityCount) unread notifications")
                    .accessibilityValue("\(model.document.notes.count) posts")
                PlazaButton { model.sheet = .compose(nil) } label: { Label("Leave a note", systemImage: "square.and.pencil") }
                Spacer(minLength: 8)
                if model.pageCount > 1 {
                    PlazaButton { model.page = max(0, model.page - 1) } label: { Image(systemName: "chevron.left") }.disabled(model.page == 0)
                    Text("\(model.page + 1) / \(model.pageCount)").monospacedDigit()
                    PlazaButton { model.page = min(model.pageCount - 1, model.page + 1) } label: { Image(systemName: "chevron.right") }.disabled(model.page + 1 == model.pageCount)
                }
                PlazaButton { if model.editing { model.editing = false } else { model.beginChangingApps() } } label: { Label(model.editing ? "Done" : "Change Apps", systemImage: model.editing ? "checkmark" : "square.grid.2x2") }
                if model.editing { PlazaButton("Undo") { model.undoLayout() }; PlazaButton("Reset Layout") { model.resetLayout() } }
                PlazaButton { model.mutate { $0.preferences.pauseMotion.toggle() } } label: { Label(model.document.preferences.pauseMotion ? "Resume" : "Pause", systemImage: model.document.preferences.pauseMotion ? "play" : "pause") }.help("Pause motion")
                PlazaButton { model.mutate { $0.preferences.ambientSound = !(model.document.preferences.ambientSound ?? true) } } label: {
                    Image(systemName: model.document.preferences.ambientSound ?? true ? "speaker.wave.1" : "speaker.slash")
                }.help(model.document.preferences.ambientSound ?? true ? "Mute plaza music" : "Play quiet plaza music")
                    .accessibilityLabel(model.document.preferences.ambientSound ?? true ? "Mute plaza music" : "Play plaza music")
                PlazaButton { model.listMode.toggle() } label: { Label(model.listMode ? "Plaza" : "List", systemImage: model.listMode ? "sun.max" : "list.bullet") }
            }.font(.system(size: 12 + (model.document.preferences.largerText == true ? 2 : 0), weight: .medium)).buttonStyle(.plain).padding(.horizontal, 30).padding(.top, 16)
            HStack {
                if model.listMode { bugReportButton }
                Text(model.status).lineLimit(1)
                Spacer()
                Text(model.isMoving ? "Local rendering · 30 fps" : "Local rendering · Still plaza")
            }.font(.system(size: 10 + (model.document.preferences.largerText == true ? 2 : 0))).foregroundStyle(.secondary).padding(.horizontal, 30).padding(.top, 12).padding(.bottom, 17)
        }.background(.white.opacity(0.55))
    }
}

/// Camera targets come from the same native ticks as the Mii and sound cues.
/// SwiftUI interpolates the transform between those targets without an extra
/// wall-clock timer, including in desktop-level windows.
private struct PlazaArrivalPresentation<Content:View>:View {
    @ObservedObject var clock:PlazaArrivalClock
    @ViewBuilder var content:(Double?)->Content
    var body:some View {
        content(clock.elapsed(at:Date()))
    }
}

private struct PlazaIslandEntrance: ViewModifier {
    @ObservedObject var clock:PlazaEntranceClock
    let slot:CGPoint
    let size:CGSize
    func body(content:Content)->some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:clock.anchor == nil || clock.finished)) { timeline in
            let t=PlazaEntrance.iconProgress(at:CrowdPoint(slot.x,slot.y),elapsed:clock.elapsed(at:timeline.date))
            let travel=pow(1-t,3)*0.65
            content
                .scaleEffect(PlazaEntrance.iconScale(progress:t))
                .offset(x:(0.5-slot.x)*size.width*travel,y:(0.44-slot.y)*size.height*travel+24*(1-t))
                .opacity(min(1,t*4))
                .allowsHitTesting(t>=1)
                .accessibilityHidden(t<1)
        }
    }
}
private struct PlazaEntranceReveal:ViewModifier {
    @ObservedObject var clock:PlazaEntranceClock
    func body(content:Content)->some View {
        content.opacity(clock.finished ? 1:0).allowsHitTesting(clock.finished)
            .accessibilityHidden(!clock.finished).animation(.easeOut(duration:0.4),value:clock.finished)
    }
}

struct IslandView: View {
    @ObservedObject var model: PlazaModel
    let app: AppIsland
    let index: Int
    let tileSize: CGFloat
    let reduceMotion: Bool
    let select: () -> Void
    @State private var hovered = false
    var body: some View {
        // Own a native hit surface above WebKit, including the app label.
        // Desktop-level windows must accept the first mouse down of a drag.
        PlazaAppControlSurface(appID: app.id, enabled: model.editing && !model.launching.contains(app.id),
                               select: select, move: { model.acceptAppDrop([$0.uuidString], onto: $1) }) { button }
            .frame(width: 154, height: tileSize + 42)
            .offset(y: 21)
    }
    @ViewBuilder private var button: some View {
        let available = model.resolvedURL(app) != nil
        PlazaButton(action: select) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isMoving || reduceMotion || model.editing)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 0.85 + Double(index) * 1.7
                let floating = !reduceMotion && !model.editing
                let lift = floating ? sin(phase) * 5 : 0
                VStack(spacing: 2) {
                    AppTile(model: model, app: app)
                        .frame(width: tileSize, height: tileSize)
                        .rotation3DEffect(.degrees(floating ? sin(phase * 0.7) * 3 : 0), axis: (x: 0, y: 1, z: 0))
                        .rotationEffect(.degrees(floating ? sin(phase * 0.55) * 1.3 : 0))
                        .scaleEffect(hovered && model.previewAppID == nil ? 1.09 : 1)
                        .offset(y: lift - (hovered && model.previewAppID == nil ? 4 : 0))
                        .overlay(alignment: .topTrailing) {
                            if model.editing { Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .bold)).padding(6).background(PlazaStyle.teal, in: Circle()).foregroundStyle(.white) }
                        }
                    Ellipse().fill(PlazaStyle.ink.opacity(0.12)).frame(width: tileSize * 0.74 - lift, height: 8).blur(radius: 3).padding(.top, 9)
                    Text(app.label).font(.system(size: 12 + (model.document.preferences.largerText == true ? 2 : 0), weight: .semibold, design: .rounded))
                        .lineLimit(1).frame(width: 145)
                        .padding(.horizontal, 4).padding(.vertical, 3).background(.white.opacity(hovered ? 0.9 : 0.65), in: Capsule())
                    if !available { Text("Locate App").font(.system(size: 9)).foregroundStyle(.orange) }
                }.frame(width: 154, height: tileSize + 42, alignment: .top)
            }
        }
        .opacity(model.previewAppID != nil && model.previewAppID != app.id ? 0.18 : 1)
        .buttonStyle(.plain)
        .onHover { value in withAnimation(.easeOut(duration: 0.18)) { hovered = value } }
        .disabled(model.launching.contains(app.id))
        .accessibilityLabel("\(model.editing ? "Edit" : "Preview") \(app.label), \(!available ? "unavailable, locate application" : "available")")
        .help(model.editing ? "Edit \(app.label)" : "Preview \(app.label), then choose Open to launch.")
        .onKeyPress(.space) { select(); return .handled }
        .contextMenu {
            PlazaButton("Preview App") { select() }
            PlazaButton("Open") { model.launch(app) }
            PlazaButton("Details & Rename…") { model.sheet = .app(app) }
            PlazaButton("Leave a note…") { model.sheet = .compose(app.id) }
            PlazaButton("Locate App…") { model.pickApp(replacing: app) }
            Divider()
            PlazaButton("Move Earlier") { model.move(app.id, delta: -1) }
            PlazaButton("Move Later") { model.move(app.id, delta: 1) }
            Divider()
            PlazaButton("Remove Shortcut", role: .destructive) { model.removeApp(app) }
        }
    }
}


struct AppTile: View {
    @ObservedObject var model: PlazaModel
    let app: AppIsland
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(red: 0.9, green: 0.94, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(nsImage: model.icon(app)).resizable().scaledToFit().padding(7)
            RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.95), lineWidth: 2)
            if model.launching.contains(app.id) { ProgressView().padding(7).background(.regularMaterial, in: Circle()) }
        }.shadow(color: PlazaStyle.ink.opacity(0.12), radius: 7, x: 0, y: 4)
    }
}

struct BubbleView: View {
    @ObservedObject var model: PlazaModel
    let offset: Int
    @State private var hovering = false
    @FocusState private var focused: Bool
    var body: some View {
        if let post = model.journalPost(at: offset) {
            let large = model.document.preferences.largerText == true
            PlazaButton { if case .journal(let id) = post.destination { model.openMiiverse(note: id) } } label: {
                HStack(alignment: .center, spacing: 9) {
                    MiiHeadIcon(avatar: post.speaker).frame(width: 42, height: 42)
                    if !post.drawing.isEmpty {
                        InkCanvas(strokes: post.drawing).scaledToFit().frame(maxHeight: 65).accessibilityHidden(true)
                    } else {
                        Text(post.text).font(.system(size: large ? 14 : 12, design: .rounded))
                            .foregroundStyle(PlazaPostStyle.text).lineSpacing(2).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 12).padding(.top, 13).padding(.bottom, 18)
                    .frame(maxWidth: .infinity).frame(height: 108).modifier(PlazaPostSurface(tailX: 30))
                    .overlay(alignment: .topLeading) { PlazaNameTab(name: post.name, large: large).padding(.leading, 10).offset(y: -7) }
            }.buttonStyle(.plain).focused($focused).help("Open Miiverse")
                .accessibilityLabel("\(post.name): \(post.accessibleText)").accessibilityHint("Open this post in the Miiverse")
                .onHover { hovering = $0; model.holdBubble(offset, held: hovering || focused) }
                .onChange(of: focused) { _, value in model.holdBubble(offset, held: hovering || value) }
                .onDisappear { model.holdBubble(offset, held: false) }
        }
    }
}


struct ToolbarButtonStyle: ButtonStyle {
    var prominent = false
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12 + (large ? 2 : 0), weight: .semibold)).padding(.horizontal, 13).frame(height: 38)
            .background(prominent ? PlazaStyle.teal : .white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(prominent ? .white : PlazaStyle.ink).opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct AppListView: View {
    @ObservedObject var model: PlazaModel
    var body: some View {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            Text("APPLICATIONS · \(model.filteredApps.count)").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                ForEach(model.filteredApps) { app in
                    HStack(spacing: 14) {
                        Image(nsImage: model.icon(app)).resizable().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.label).font(.headline)
                            Text(model.resolvedURL(app) == nil ? "Application unavailable · Locate App to reconnect" : "Ready to open").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        PlazaButton("Details") { model.sheet = .app(app) }.accessibilityLabel("Details for \(app.label)")
                        PlazaButton(model.resolvedURL(app) == nil ? "Locate App" : "Open") { if model.resolvedURL(app) == nil { model.pickApp(replacing: app) } else { model.launch(app) } }.disabled(model.launching.contains(app.id)).accessibilityLabel("\(model.resolvedURL(app) == nil ? "Locate" : "Open") \(app.label)")
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .contain)
                }
            SocialFriendList(model: model, social: model.social)
            Text("PLAZA JOURNAL · \(model.visibleNotes.count)").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                ForEach(model.visibleNotes) { note in
                    PlazaButton { model.openMiiverse(note: note.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(model.noteDisplayName(note)) · \(model.isOwnNote(note) ? note.visibility.label + " note" : note.visibility.label + " post")").font(.caption).foregroundStyle(PlazaStyle.teal)
                            Text(note.drawing.isEmpty ? note.text : note.drawingDescription).lineLimit(3)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                if model.visibleNotes.isEmpty { Text("Your notes and sketches will appear here.").foregroundStyle(.secondary) }
          }.padding(.bottom, 20)
        }.padding(.horizontal, 30)
    }
}

/// Wallpaper actors may cross the safe margins; ordinary windows retain their
/// header/footer clip while the renderer itself has room beyond the camera.
private struct PlazaActorClip:Shape {
    var unbounded:Bool
    func path(in rect:CGRect)->Path {Path(unbounded ? rect.insetBy(dx:-rect.width,dy:-rect.height):rect)}
}
