import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PlazaCore

/// A dedicated entry menu. Drafts only join the plaza after Save Mii.
struct MiiMakerView: View {
    private enum Screen { case menu, create, library, editor }
    @ObservedObject var model: PlazaModel
    var onClose:(()->Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var screen: Screen = .menu
    @State private var editingID: UUID?
    @State private var draft: Avatar?
    @State private var fileOptions = false

    var body: some View {
        ZStack {
            MakerBackground().accessibilityHidden(true)
            if screen == .editor {
                CharacterEditor(model: model, initialID: editingID, initialAvatar: draft, onClose: { navigate(.menu) })
                    .id(draft?.id ?? editingID).transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.square.fill").font(.system(size: 30)).foregroundStyle(Color(red: 0.40, green: 0.64, blue: 0.28))
                        Text("Mii Maker").font(.system(size: 30, weight: .medium, design: .rounded))
                        Spacer()
                        Text("\(model.document.avatars.count) / 12 Miis").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 38).padding(.top, 28)
                    Spacer(minLength: 20)
                    switch screen {
                    case .menu: menu
                    case .create: create
                    case .library: library
                    case .editor: EmptyView()
                    }
                    Spacer(minLength: 20)
                    HStack(spacing: 20) {
                        Button {
                            if screen == .menu { if let onClose {onClose()} else {dismiss()} } else { navigate(.menu) }
                        } label: { Label(screen == .menu ? "Back to plaza" : "Back", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(MakerPillStyle()).keyboardShortcut(.cancelAction)
                        Spacer()
                        Button { model.mutate { $0.preferences.ambientSound = !(model.document.preferences.ambientSound ?? true) } } label: {
                            Image(systemName: model.document.preferences.ambientSound ?? true ? "speaker.wave.1" : "speaker.slash")
                        }.buttonStyle(.plain).accessibilityLabel(model.document.preferences.ambientSound ?? true ? "Mute music" : "Play music")
                        Slider(value: Binding(get: { model.document.preferences.makerMusicVolume ?? 0.10 }, set: { value in model.mutate { $0.preferences.makerMusicVolume = value } }), in: 0...0.35)
                            .frame(width: 110).tint(PlazaStyle.teal).accessibilityLabel("Mii Maker music volume")
                        Text("\(Int((model.document.preferences.makerMusicVolume ?? 0.10) * 100))%")
                            .font(.system(size: 11)).monospacedDigit().frame(width: 30)
                    }.padding(.horizontal, 32).padding(.bottom, 24)
                }.transition(.opacity)
            }
        }
        .frame(width: 960, height: 760)
        .foregroundStyle(PlazaStyle.ink)
        .onAppear { model.updateAudio() }
        .onChange(of: model.musicTrack) { _, _ in model.updateAudio() }
        .onChange(of: model.audioEligible) { _, _ in model.updateAudio() }
        .onChange(of: model.document.preferences.ambientSound) { _, _ in model.updateAudio() }
        .onChange(of: model.document.preferences.makerMusicVolume) { _, _ in model.updateAudio() }
        .onDisappear { model.updateAudio() }
    }

    private var menu: some View {
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                Button { navigate(.create) } label: {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 70, weight: .light)).foregroundStyle(Color(red: 0.30, green: 0.55, blue: 0.25))
                        Text("Create Mii").font(.system(size: 28, weight: .medium, design: .rounded))
                    }.frame(width: 242, height: 214)
                        .background(LinearGradient(colors: [.white.opacity(0.6), Color(red: 0.75, green: 0.91, blue: 0.49).opacity(0.6)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 26))
                }.buttonStyle(MakerTileStyle()).disabled(model.document.avatars.count >= 12)
                Button { fileOptions = false; navigate(.library) } label: {
                    VStack(spacing: 17) {
                        HStack(spacing: -14) {
                            ForEach(Array(model.document.avatars.prefix(3))) { avatar in
                                AvatarPortrait(avatar: avatar).frame(width: 67, height: 91)
                            }
                        }.frame(height: 92).accessibilityHidden(true)
                        Text("Select Mii").font(.system(size: 28, weight: .medium, design: .rounded))
                    }.frame(width: 242, height: 214)
                        .background(LinearGradient(colors: [.white.opacity(0.6), Color(red: 0.97, green: 0.82, blue: 0.60).opacity(0.5)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 26))
                }.buttonStyle(MakerTileStyle())
            }
            Button(action: importMii) { Label("Import Mii from File…", systemImage: "square.and.arrow.down").frame(width: 474) }.buttonStyle(MakerPillStyle()).disabled(model.document.avatars.count >= 12)
            Button { fileOptions = true; navigate(.library) } label: { Label("Mii Files & Portraits", systemImage: "photo.on.rectangle.angled").frame(width: 474) }.buttonStyle(MakerPillStyle())
            Text(model.document.avatars.count >= 12 ? "Your Mii library is full. Select a Mii to edit it." : "Your creations will join you in the middle of the plaza.")
                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 4)
        }
    }
    private var create: some View {
        VStack(spacing: 28) {
            Text("Choose a starting Mii.").font(.system(size: 25, weight: .medium, design: .rounded))
            HStack(spacing: 30) {
                ForEach(0..<2) { gender in
                    Button {
                        var avatar = Avatar(name: "New Mii", outfit: gender == 0 ? 0 : 1)
                        avatar.features.gender = gender; avatar.hair = gender == 0 ? 33 : 12
                        draft = avatar; editingID = nil; navigate(.editor)
                    } label: {
                        VStack(spacing: 18) {
                            Image(systemName: gender == 0 ? "figure.stand" : "figure.stand.dress").font(.system(size: 74)).foregroundStyle(gender == 0 ? Color.blue.opacity(0.65) : Color(red: 0.86, green: 0.45, blue: 0.37))
                            Text(gender == 0 ? "Male" : "Female").font(.system(size: 25, weight: .medium, design: .rounded))
                        }.frame(width: 210, height: 215)
                    }.buttonStyle(MakerTileStyle())
                }
            }
            Text("Make every feature your own in the editor.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private var library: some View {
        VStack(spacing: 20) {
            Text(fileOptions ? "Choose a Mii for files & portraits." : "Choose a Mii to edit.")
                .font(.system(size: 25, weight: .medium, design: .rounded))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(160), spacing: 16), count: 4), spacing: 16) {
                    ForEach(model.document.avatars) { avatar in
                        Button {
                            editingID = avatar.id; draft = nil; navigate(.editor)
                        } label: {
                            VStack(spacing: 7) {
                                AvatarPortrait(avatar: avatar).frame(width: 84, height: 108).accessibilityHidden(true)
                                HStack(spacing: 4) {
                                    if model.document.primaryAvatarID == avatar.id { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                                    Text(avatar.name).lineLimit(1)
                                }.font(.system(size: 13, weight: .semibold, design: .rounded))
                            }.frame(width: 150, height: 156)
                        }.buttonStyle(MakerTileStyle()).accessibilityLabel("Edit \(avatar.name)")
                    }
                }.padding(8)
            }.frame(height: 360)
            if fileOptions { Text("Use Files in the editor to export a Mii, character JSON, or a portrait PNG.").font(.system(size: 13)).foregroundStyle(.secondary) }
        }
    }
    private func navigate(_ next: Screen) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { screen = next }
    }
    private func importMii() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "mii") ?? .data, UTType(filenameExtension: "ffsd") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 100_000 else { throw PlazaError.invalid("Mii files must be smaller than 100 KB.") }
            let data = try Data(contentsOf: url)
            var avatar = url.pathExtension.lowercased() == "json" ? try JSONDecoder().decode(Avatar.self, from: data).validated() : try MiiFile.decode(data)
            avatar.id = UUID(); draft = avatar; editingID = nil; navigate(.editor)
        } catch { model.error = error.localizedDescription }
    }
}

private struct MakerTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(7)
            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(.white, lineWidth: 3))
            .shadow(color: PlazaStyle.ink.opacity(0.16), radius: 3, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
private struct MakerPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 19, weight: .medium, design: .rounded))
            .padding(.horizontal, 22).padding(.vertical, 15)
            .background(LinearGradient(colors: [.white, Color.white.opacity(0.72)], startPoint: .top, endPoint: .bottom), in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
            .shadow(color: PlazaStyle.ink.opacity(0.15), radius: 3, y: 4)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct MakerBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 0.70, green: 0.91, blue: 0.72), Color(red: 0.92, green: 0.97, blue: 0.72), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color(red: 0.73, green: 0.89, blue: 0.91).opacity(0.55))
                    .frame(width: proxy.size.width * 1.8, height: proxy.size.height * 0.65)
                    .rotationEffect(.degrees(10)).position(x: proxy.size.width * 0.30, y: proxy.size.height * 0.83)
                Ellipse().fill(.white.opacity(0.5))
                    .frame(width: proxy.size.width * 1.6, height: proxy.size.height * 0.60)
                    .rotationEffect(.degrees(-12)).position(x: proxy.size.width * 0.85, y: proxy.size.height * 0.96)
            }.clipped()
        }
    }
}
