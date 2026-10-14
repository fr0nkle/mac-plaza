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
                Button { model.sheet = .preferences } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 17 + (model.document.preferences.largerText == true ? 2 : 0))) }.buttonStyle(.plain).help("Preferences")
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
                    if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                }.padding(10).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                Button { model.sheet = .characters } label: {
                    HStack(spacing: 6) {
                        Group { if model.document.preferences.safeMode { Image(nsImage: AvatarArtwork.face(model.document.primaryAvatar)).resizable().scaledToFit() } else { AvatarPortrait(avatar:model.document.primaryAvatar) } }.frame(width:25,height:32)
                        Text("Characters")
                    }
                }.buttonStyle(ToolbarButtonStyle(large:model.document.preferences.largerText == true)).contextMenu { Button("View Your Profile") { model.sheet = .profile(model.document.primaryAvatar) } }
                Button { model.pickApp() } label: { Label("Add App", systemImage: "plus") }.buttonStyle(ToolbarButtonStyle(prominent:true,large:model.document.preferences.largerText == true)).keyboardShortcut("n", modifiers: .command)
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
            ZStack {
              ZStack {
                if !model.document.preferences.safeMode { SceneView(scene:model.scene,moving:model.isMoving && !reduceMotion,onSelect:model.openCharacter).accessibilityHidden(true) }
                if selected == nil { VStack(spacing: 7) {
                    Text("MAKE YOURSELF AT HOME").font(.system(size: 9 + (model.document.preferences.largerText == true ? 2 : 0), weight: .semibold)).tracking(2.6).foregroundStyle(PlazaStyle.teal.opacity(0.7))
                    Text("Miis · \(model.document.preferences.population) in the plaza").font(.system(size: 10 + (model.document.preferences.largerText == true ? 2 : 0))).foregroundStyle(.secondary)
                }.position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.96).accessibilityHidden(true) }
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
                                     journalPost: model.postPresentation == .journal ? model.journalPost() : nil,
                                     onSelectJournal: { model.openJournal(note: $0) },
                                     largerText: model.document.preferences.largerText == true, islands: Array(slots.prefix(model.visibleApps.count)),
                                     reserved: [],
                                     onSelect: { model.sheet = .friend($0) }).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .modifier(PlazaEntranceReveal(clock:model.scene.entranceClock))
                }
                if model.visibleApps.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: model.search.isEmpty ? "plus.app" : "magnifyingglass").font(.system(size: 35 + (model.document.preferences.largerText == true ? 2 : 0))).foregroundStyle(PlazaStyle.teal)
                        Text(model.search.isEmpty ? "Your plaza starts here." : "No apps found.").font(.title3)
                        Button("Add an application") { model.pickApp() }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal)
                    }.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
              }
              .background {
                  PlazaGround(viewportSize: proxy.size)
                      .frame(width: proxy.size.width * 2, height: proxy.size.height * 2)
                      .accessibilityHidden(true)
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
                          PlazaControlSurface { plazaZoomControls(size: proxy.size) }
                              .frame(width: 136, height: 40)
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
                          Button(action: closePreview) { Label("Back to plaza", systemImage: "chevron.left") }
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
                          Button("Skip") {model.scene.finishArrival()}.keyboardShortcut(.cancelAction)
                      }.padding(.horizontal,24).padding(.vertical,14)
                          .background(.regularMaterial,in:Capsule())
                  }.padding(.bottom,30).zIndex(4)
              }
            }
            .background(PlazaGround().accessibilityHidden(true))
            .background(PlazaNavigationInput(enabled: selected == nil && model.sheet == nil && arrivalTime == nil, canPan: !model.editing, zoom: zoom, offset: offset,
                onZoom: { setPlazaZoom($0, size: proxy.size) },
                onPan: { plazaOffset = PlazaViewport.offset($0, zoom: plazaZoom, size: proxy.size) }))
            .clipped()
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
    private func setPlazaZoom(_ value: CGFloat, size: CGSize) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.22,0.61,0.36,1,duration:0.32)) {
            plazaZoom = PlazaViewport.zoom(value)
            plazaOffset = PlazaViewport.offset(plazaOffset, zoom: plazaZoom, size: size)
        }
        if !desktop { model.window?.isMovableByWindowBackground = plazaZoom <= 1 }
    }
    private func plazaZoomControls(size: CGSize) -> some View {
        HStack(spacing: 9) {
            Button { setPlazaZoom(plazaZoom - 0.15, size: size) } label: {
                Image(systemName: "minus").frame(width: 30, height: 30).contentShape(Rectangle())
            }.disabled(plazaZoom <= PlazaViewport.zoomRange.lowerBound)
                .accessibilityLabel("Zoom out of plaza").help("Zoom out (⌘−)")
                .keyboardShortcut("-", modifiers: .command)
            Button {
                setPlazaZoom(1, size: size)
                plazaOffset = .zero
            } label: {
                Text("\(Int((plazaZoom * 100).rounded()))%")
                    .monospacedDigit().frame(width: 48, height: 30).contentShape(Rectangle())
            }.accessibilityLabel("Reset plaza zoom to 100 percent")
                .accessibilityValue("\(Int((plazaZoom * 100).rounded())) percent")
                .help("Reset zoom (⌘0). Pinch to zoom; drag to explore when zoomed in.")
                .keyboardShortcut("0", modifiers: .command)
            Button { setPlazaZoom(plazaZoom + 0.15, size: size) } label: {
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
    private var desktopControls: some View {
        HStack(spacing: 14) {
            if model.pageCount > 1 {
                Button { model.page = max(0, model.page - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(model.page == 0).accessibilityLabel("Previous apps")
                Text("\(model.page + 1) / \(model.pageCount)").monospacedDigit()
                Button { model.page = min(model.pageCount - 1, model.page + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(model.page + 1 == model.pageCount).accessibilityLabel("Next apps")
            }
            Button { model.openJournal() } label: { Image(systemName: "text.bubble") }.help("Plaza journal")
            Button { model.sheet = .preferences } label: { Image(systemName: "slider.horizontal.3") }.help("Preferences")
            Button("Return to Desktop · Esc") { model.desktop.returnToDesktop() }
        }.font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
            .padding(12).background(.regularMaterial, in: Capsule())
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(PlazaStyle.ink.opacity(0.07)).frame(height: 1)
            HStack(spacing: 20) {
                Button { model.openJournal() } label: {
                    Label("Plaza journal", systemImage: "text.bubble")
                    Text("\(model.document.notes.count)").font(.system(size: 10 + (model.document.preferences.largerText == true ? 2 : 0), weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3).background(PlazaStyle.teal.opacity(0.1), in: Capsule())
                }
                Button { model.sheet = .compose(nil) } label: { Label("Leave a note", systemImage: "square.and.pencil") }
                Spacer(minLength: 8)
                if model.pageCount > 1 {
                    Button { model.page = max(0, model.page - 1) } label: { Image(systemName: "chevron.left") }.disabled(model.page == 0)
                    Text("\(model.page + 1) / \(model.pageCount)").monospacedDigit()
                    Button { model.page = min(model.pageCount - 1, model.page + 1) } label: { Image(systemName: "chevron.right") }.disabled(model.page + 1 == model.pageCount)
                }
                Button { if model.editing { model.editing = false } else { model.beginChangingApps() } } label: { Label(model.editing ? "Done" : "Change Apps", systemImage: model.editing ? "checkmark" : "square.grid.2x2") }
                if model.editing { Button("Undo") { model.undoLayout() }; Button("Reset Layout") { model.resetLayout() } }
                Button { model.mutate { $0.preferences.pauseMotion.toggle() } } label: { Label(model.document.preferences.pauseMotion ? "Resume" : "Pause", systemImage: model.document.preferences.pauseMotion ? "play" : "pause") }.help("Pause motion")
                Button { model.mutate { $0.preferences.ambientSound = !(model.document.preferences.ambientSound ?? true) } } label: {
                    Image(systemName: model.document.preferences.ambientSound ?? true ? "speaker.wave.1" : "speaker.slash")
                }.help(model.document.preferences.ambientSound ?? true ? "Mute plaza music" : "Play quiet plaza music")
                    .accessibilityLabel(model.document.preferences.ambientSound ?? true ? "Mute plaza music" : "Play plaza music")
                Button { model.listMode.toggle() } label: { Label(model.listMode ? "Plaza" : "List", systemImage: model.listMode ? "sun.max" : "list.bullet") }
            }.font(.system(size: 12 + (model.document.preferences.largerText == true ? 2 : 0), weight: .medium)).buttonStyle(.plain).padding(.horizontal, 30).padding(.top, 16)
            HStack {
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
        Button(action: select) {
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
            Button("Preview App") { select() }
            Button("Open") { model.launch(app) }
            Button("Details & Rename…") { model.sheet = .app(app) }
            Button("Leave a note…") { model.sheet = .compose(app.id) }
            Button("Locate App…") { model.pickApp(replacing: app) }
            Divider()
            Button("Move Earlier") { model.move(app.id, delta: -1) }
            Button("Move Later") { model.move(app.id, delta: 1) }
            Divider()
            Button("Remove Shortcut", role: .destructive) { model.removeApp(app) }
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
    private let guides = ["Make yourself at home. Click an app to take a closer look before opening it.", "A thought, a sketch, a little spark. Leave a note in your journal.", "These visitors live on your Mac. Give your own characters a little personality."]
    var body: some View {
        let index = model.bubbleSelections[offset] % (model.bubbleNotes.count + guides.count)
        let note = index < model.bubbleNotes.count ? model.bubbleNotes[index] : nil
        let author = note.map { model.noteAvatar($0) } ?? model.document.primaryAvatar
        let large = model.document.preferences.largerText == true
        Button { model.openJournal(note: note?.id) } label: {
            HStack(alignment: .center, spacing: 9) {
                MiiHeadIcon(avatar: author).frame(width: 42, height: 42)
                if let note, !note.drawing.isEmpty {
                    InkCanvas(strokes: note.drawing).scaledToFit().frame(maxHeight: 65).accessibilityHidden(true)
                } else {
                    Text(note?.text ?? guides[index - model.bubbleNotes.count])
                        .font(.system(size: large ? 14 : 12, design: .rounded))
                        .foregroundStyle(PlazaPostStyle.text).lineSpacing(2).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.horizontal, 12).padding(.top, 13).padding(.bottom, 18)
                .frame(maxWidth: .infinity).frame(height: 108)
                .modifier(PlazaPostSurface(tailX: 30))
                .overlay(alignment: .topLeading) {
                    PlazaNameTab(name: note?.author ?? "Plaza Guide", large: large).padding(.leading, 10).offset(y: -7)
                }
        }.buttonStyle(.plain).focused($focused)
            .help("Open plaza journal")
            .accessibilityLabel("\(note?.author ?? "Plaza Guide"): \(note.map { $0.drawing.isEmpty ? $0.text : $0.drawingDescription } ?? guides[index - model.bubbleNotes.count])")
            .accessibilityHint("Open this post in the plaza journal")
            .onHover { hovering = $0; model.holdBubble(offset, held:hovering || focused) }
            .onChange(of: focused) { _, value in model.holdBubble(offset, held:hovering || value) }
            .onDisappear { model.holdBubble(offset, held:false) }
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
                        Button("Details") { model.sheet = .app(app) }.accessibilityLabel("Details for \(app.label)")
                        Button(model.resolvedURL(app) == nil ? "Locate App" : "Open") { if model.resolvedURL(app) == nil { model.pickApp(replacing: app) } else { model.launch(app) } }.disabled(model.launching.contains(app.id)).accessibilityLabel("\(model.resolvedURL(app) == nil ? "Locate" : "Open") \(app.label)")
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .contain)
                }
            SocialFriendList(model: model, social: model.social)
            Text("PLAZA JOURNAL · \(model.visibleNotes.count)").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                ForEach(model.visibleNotes) { note in
                    Button { model.openJournal(note: note.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(model.noteDisplayName(note)) · \(model.isOwnNote(note) ? (note.shared == true ? "Public note" : "Private note") : "Friend’s note")").font(.caption).foregroundStyle(PlazaStyle.teal)
                            Text(note.drawing.isEmpty ? note.text : note.drawingDescription).lineLimit(3)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
                if model.visibleNotes.isEmpty { Text("Your notes and sketches will appear here.").foregroundStyle(.secondary) }
          }.padding(.bottom, 20)
        }.padding(.horizontal, 30)
    }
}
