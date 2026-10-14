import SwiftUI
import PlazaCore

/// Browse a live roster without replacing the renderer behind the menu.
struct FriendsMenuView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedID: String?

    private var friends: [SharedMii] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return FriendMiiAssignments.prioritizedFriends(social.friends.filter {
            query.isEmpty || $0.displayName.localizedStandardContains(query)
        })
    }
    private var selected: SharedMii? {
        friends.first(where: { $0.id == selectedID }) ?? friends.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.document.preferences.privatePresentation {
                ContentUnavailableView("Friend details are hidden", systemImage: "eye.slash",
                    description: Text("Turn off Private Presentation in Settings to view your friends."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    roster.frame(width: 300)
                    Divider().padding(.vertical, 12)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.padding(.horizontal, 28).padding(.vertical, 20)
            }
            footer
        }
        .frame(width: 960, height: 760)
        .foregroundStyle(PlazaStyle.ink)
        .background(MakerBackground())
        .onAppear { model.updateAudio() }
        .onChange(of: model.audioEligible) { _, _ in model.updateAudio() }
        .onChange(of: model.document.preferences.friendsMusicVolume) { _, _ in model.updateAudio() }
        .onChange(of: model.document.preferences.ambientSound) { _, _ in model.updateAudio() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.2.fill").font(.system(size: 30)).foregroundStyle(PlazaStyle.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Friends").font(.system(size: 30, weight: .medium, design: .rounded))
                Text(social.previewing ? "Sample friends · Preview only" : "A familiar face, wherever they are.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            PlazaButton("Discord & Friends…") { model.sheet = .social }.buttonStyle(.bordered)
                .help("Manage your Discord connection and sharing")
        }.padding(.horizontal, 38).padding(.top, 30)
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search friends", text: $search).textFieldStyle(.plain)
                    .accessibilityLabel("Search friends")
                if !search.isEmpty {
                    PlazaButton { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear friend search")
                }
            }.padding(12).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            Text("\(friends.count) of \(social.friends.count) friends")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(friends) { friend in
                        PlazaButton { selectedID = friend.id } label: {
                            HStack(spacing: 12) {
                                AvatarPortrait(avatar: friend.avatar).frame(width: 40, height: 52)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(friend.displayName).font(.headline).lineLimit(1)
                                    FriendStatusLabel(friend: friend)
                                    if friend.locallyAssignedAvatar == true {
                                        Text("Assigned Mii").font(.caption2).foregroundStyle(PlazaStyle.teal)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected?.id == friend.id ? .white : .white.opacity(0.45),
                                            in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(selected?.id == friend.id ? PlazaStyle.teal.opacity(0.5) : .clear))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("View \(friend.displayName), \(friend.presence.label)")
                    }
                    if friends.isEmpty && !social.friends.isEmpty {
                        Text("No friends match your search.").foregroundStyle(.secondary).padding(.top, 30)
                    }
                }
            }
            Text(social.discordFriendsMessage).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }.padding(.trailing, 20)
    }

    @ViewBuilder private var detail: some View {
        if let friend = selected {
            ScrollView {
                VStack(spacing: 16) {
                    AvatarPortrait(avatar: friend.avatar).frame(width: 130, height: 168)
                        .accessibilityLabel("Mii for \(friend.displayName)")
                    Text(friend.displayName).font(.system(size: 27, weight: .medium, design: .rounded))
                        .textSelection(.enabled)
                    FriendStatusLabel(friend: friend)
                    if let status = friend.customStatus, status.isCurrent {
                        Text(status.text).font(.body).textSelection(.enabled).multilineTextAlignment(.center)
                    }
                    ForEach(Array(friend.activities.filter { $0.isRecent() }.enumerated()), id: \.offset) { _, activity in
                        Label(activity.label, systemImage: activity.source == "discord" ? "gamecontroller" : "app")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !friend.note.isEmpty {
                        Text(friend.note).font(.callout).textSelection(.enabled)
                            .padding(16).frame(maxWidth: .infinity)
                            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
                    }
                    assignment(for: friend)
                }.padding(.horizontal, 28).padding(.vertical, 18)
            }
        } else if social.friends.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "person.2.crop.square.stack").font(.system(size: 64, weight: .light))
                    .foregroundStyle(PlazaStyle.teal)
                Text("Make room for your friends.").font(.system(size: 24, weight: .medium, design: .rounded))
                Text("Connect Discord to see your friends’ Miis and availability. Choose a friend to assign a Mii from your library.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                PlazaButton("Connect Discord & Friends…") { model.sheet = .social }
                    .buttonStyle(.borderedProminent).tint(PlazaStyle.teal)
            }.padding(42)
        } else {
            ContentUnavailableView.search(text: search)
        }
    }

    private func assignment(for friend: SharedMii) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Their Mii").font(.headline)
            if friend.temporaryAvatar == true, friend.discordID != nil {
                Picker("Assigned Mii", selection: Binding<UUID?>(
                    get: { social.assignedMiiID(for: friend) },
                    set: { social.assignMii($0, to: friend.id) })) {
                    Text("Random Mii (automatic)").tag(Optional<UUID>.none)
                    ForEach(model.document.avatars) { avatar in
                        Text(avatar.name).tag(Optional(avatar.id))
                    }
                }.accessibilityLabel("Assigned Mii for \(friend.displayName)")
                Text("Saved on this Mac. Assignments stay attached to this friend, with their status and game activity. A Mii they share themselves takes priority.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("This friend shares their own Mii.", systemImage: "person.crop.circle.badge.checkmark")
                Text("Their chosen appearance updates automatically.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
    }

    private var footer: some View {
        HStack(spacing: 18) {
            PlazaButton(sound: .back) { if let onClose { onClose() } else { dismiss() } } label: {
                Label("Back to plaza", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(.white.opacity(0.85), in: Capsule())
            }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            Spacer()
            PlazaButton { model.mutate { $0.preferences.ambientSound = !(model.document.preferences.ambientSound ?? true) } } label: {
                Image(systemName: model.document.preferences.ambientSound ?? true ? "speaker.wave.1" : "speaker.slash")
            }.buttonStyle(.plain).accessibilityLabel(model.document.preferences.ambientSound ?? true ? "Mute music" : "Play music")
            Slider(value: Binding(get: { model.document.preferences.friendsMusicVolume ?? 0.10 }, set: { value in
                model.mutate { $0.preferences.friendsMusicVolume = value }
            }), in: 0...0.35).frame(width: 110).tint(PlazaStyle.teal).accessibilityLabel("Friends music volume")
            Text("\(Int((model.document.preferences.friendsMusicVolume ?? 0.10) * 100))%")
                .font(.system(size: 11)).monospacedDigit().frame(width: 30)
        }.padding(.horizontal, 32).padding(.bottom, 24)
    }
}
