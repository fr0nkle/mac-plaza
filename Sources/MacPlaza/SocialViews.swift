import AppKit
import SwiftUI
import PlazaCore

struct SocialActivityModifier: ViewModifier {
    @ObservedObject var model: PlazaModel
    private var active: Bool { model.renderVisible && model.sessionActive && !model.document.preferences.safeMode }
    private var activityEligible: Bool { model.sessionActive && !model.document.preferences.safeMode }
    func body(content: Content) -> some View {
        content.onAppear { model.social.setActivityEligible(activityEligible); model.social.setActive(active) }
            .onChange(of: active) { _, value in model.social.setActive(value) }
            .onChange(of: activityEligible) { _, value in model.social.setActivityEligible(value) }
    }
}

extension FriendPresence {
    var color: Color {
        switch self { case .online: return .green; case .idle: return .orange; case .dnd: return .red; case .offline, .unknown: return .gray }
    }
}

struct SocialConnectionBadge: View {
    @ObservedObject var social: SocialController
    var action: () -> Void
    var body: some View {
        PlazaButton(action: action) {
            Label(social.previewing ? "FRIENDS PREVIEW" : social.connected ? "PLAZA FRIENDS" : "DISCORD & FRIENDS",
                  systemImage: "person.2.fill")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(PlazaStyle.teal)
                .padding(.horizontal, 13).padding(.vertical, 8).background(PlazaStyle.teal.opacity(0.07), in: Capsule())
        }.buttonStyle(.plain).help("Discord account and Plaza friends")
    }
}

struct FriendStatusLabel: View {
    let friend: SharedMii
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(friend.presence.color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(friend.presence.label)
            if friend.plazaOnline { Text("· In Plaza") }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private func matchingFriends(_ friends: [SharedMii], query: String) -> [SharedMii] {
    let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matches = name.isEmpty ? friends : friends.filter { $0.displayName.localizedStandardContains(name) }
    return FriendMiiAssignments.prioritizedFriends(matches)
}

private struct DiscordFriendSearchField: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search Discord friends", text: $query)
                .textFieldStyle(.plain).accessibilityLabel("Search Discord friends")
            if !query.isEmpty {
                PlazaButton { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Clear friend search").help("Clear friend search")
            }
        }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SocialSettingsView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var note = ""
    @State private var sharing = false
    @State private var sharePresence = false
    @State private var shareActivity = false
    @State private var shareDiscordFriends = false
    @State private var friendCode = ""
    @State private var confirmUnlink = false
    @State private var showBlocks = false
    @State private var friendSearch = ""
    private var visibleFriends: [SharedMii] { matchingFriends(social.friends, query: friendSearch) }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Discord & Plaza friends", subtitle: "Your Mii, your friends, a little note overhead.") { dismiss() }
            Form {
                Section(social.hasSession ? "Discord connection" : "1. Connect your Discord account") {
                    Text(social.message).font(.callout).textSelection(.enabled)
                    if social.previewing {
                        PlazaButton("End Sample Preview") { social.endPreview() }
                    } else {
                        Text("Sign in, choose your Mii, and share it with your Discord friends. No Plaza invitation codes needed.").font(.callout)
                        DisclosureGroup("Advanced connection settings") {
                            TextField("Plaza service address", text: $social.serverAddress, prompt: Text("https://plaza.example.com"))
                                .textFieldStyle(.roundedBorder).disabled(social.hasSession || social.busy)
                            TextField("Discord Application ID", text: $social.discordApplicationID)
                                .textFieldStyle(.roundedBorder).disabled(social.busy || social.connectingLocally)
                            Text("For direct sign-in, the app owner enables Public Client and registers http://127.0.0.1/callback in Discord’s Developer Portal once. Each person’s authorization stays in their own Keychain.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            PlazaButton(social.usesLocalDiscord ? "Reconnect Discord on This Mac" : "Connect Discord on This Mac") { social.connectLocally() }
                                .disabled(social.busy || social.connectingLocally || (UInt64(social.discordApplicationID) ?? 0) == 0)
                            if social.hasSession || social.hasDiscordFriendsAuthorization || social.connectingLocally {
                                PlazaButton("Disconnect This Device") { social.disconnectLocalDiscord() }
                            }
                            if social.connectingLocally { ProgressView().controlSize(.small) }
                        }
                        Text(social.usesLocalDiscord ? "Discord friends connect directly. The Plaza service is optional for friends and supplies shared delivery and bot activity." : "Direct sign-in keeps Discord friends working when the Plaza service is offline. Service sign-in remains available below.")
                            .font(.caption).foregroundStyle(.secondary)
                        if social.pendingInteractionCount > 0 {
                            Text("\(social.pendingInteractionCount) interaction(s) saved on this Mac, waiting for delivery.").font(.callout)
                        }
                        HStack {
                            if !social.hasSession {
                                PlazaButton("Connect Discord") { social.connect() }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal)
                                    .disabled(social.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || social.busy)
                                PlazaButton("Preview Sample Friends") { social.preview(); dismiss() }.disabled(social.busy)
                            } else {
                                PlazaButton(social.hasDiscordFriendsAuthorization ? "Reconnect Discord Friends" : "Load My Discord Friends") { social.connect() }
                                    .buttonStyle(.borderedProminent).tint(PlazaStyle.teal).disabled(social.busy)
                                PlazaButton("Change Service") { social.changeService() }.disabled(social.busy)
                                PlazaButton("Refresh") { Task { await social.refresh() } }.disabled(social.busy)
                                PlazaButton("Unlink & Delete Shared Account…", role: .destructive) { confirmUnlink = true }.disabled(social.busy)
                            }
                            if social.busy { ProgressView().controlSize(.small) }
                        }
                        if social.hasSession { Text(social.discordFriendsMessage).font(.callout) }
                        Text("Sign-in requests your identity and Discord friends’ availability. Your Discord friends appear automatically with random Miis; no Plaza invitation or bot installation is required.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if social.account != nil || social.hasDiscordFriendsAuthorization {
                    if social.account != nil {
                    Section("2. Link your Mii & choose what to share") {
                        Picker("Mii to publish", selection: $selected) {
                            ForEach(model.document.avatars) { avatar in Text(avatar.name).tag(Optional(avatar.id)) }
                        }
                        PlazaButton("Create or edit a Mii…") { model.sheet = .characters }
                        TextField("A little note for your friends", text: $note, axis: .vertical).lineLimit(3...5)
                        Text("\(note.count)/280 characters").font(.caption).foregroundStyle(note.count > 280 ? .red : .secondary)
                        Toggle("Share my chosen Mii and note with my Discord friends", isOn: Binding(get: { sharing && shareDiscordFriends }, set: { sharing = $0; shareDiscordFriends = $0 }))
                        Text("With automatic sharing on, this Mac sends your current Discord friend IDs as the allowed audience for your Mii and note. It updates while connected; friends do not need a Plaza invitation. Turn sharing off and save to revoke access.").font(.caption).foregroundStyle(.secondary)
                        Toggle("Share my Discord availability and whether I’m in Plaza", isOn: $sharePresence)
                        Toggle("Share my current and recently used apps & games", isOn: $shareActivity)
                        Text("Friends without a shared Mii receive a random temporary Mii for each sign-in or app session. Custom status text appears periodically overhead. Remembered Discord games can alternate with it, and shared notes can appear too.").font(.caption).foregroundStyle(.secondary)
                        Text("Optional activity sharing sends foreground application names and bundle IDs while this Mac is awake, including when Plaza is in the background. Friends gather around matching app islands. Shared Plaza app activity expires after 30 minutes; window titles, documents, and app contents are never shared.").font(.caption).foregroundStyle(.secondary)
                        PlazaButton("Save Shared Profile") {
                            if let avatar = model.document.avatars.first(where: { $0.id == selected }) {
                                social.publish(avatar: avatar, note: note, sharing: sharing, sharePresence: sharePresence, shareActivity: shareActivity, shareDiscordFriends: shareDiscordFriends)
                            }
                        }.disabled(social.busy || selected == nil || note.count > 280)
                        Text(social.discordSharingMessage).font(.caption).foregroundStyle(.secondary)
                        Text("Saving publishes this Mii’s appearance and note. Birthdays, creator details, private notes, drafts, local replies, app paths and renderer resources stay on your Mac. Public Miiverse posts and their author Miis/drawings share independently with your Discord friends. Discord friends’ availability comes directly from Discord. Custom status text and other games use the optional bot and respect Discord’s server visibility and profile privacy settings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Discord custom statuses & games") {
                        Toggle("Show custom statuses & games from shared Discord servers", isOn: Binding(get: { social.showDiscordGames }, set: { social.setDiscordGamesEnabled($0) }))
                        Text(social.discordGamesMessage).font(.callout)
                        if let install = social.botInstallURL {
                            Link("Add Plaza bot to a shared Discord server…", destination: install)
                            Text("A server administrator only needs to do this once. If the bot is already installed in a shared server, you’re ready.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Friends’ custom Discord status text appears overhead when visible to the Plaza bot in a server you both share. Discord may hide it based on their profile privacy settings. Generic online, away, busy and offline bubbles are hidden. Game activity still gathers Miis around matching homescreen apps; add the game with the same name Discord displays. No Plaza invitation or linked Mii is needed.").font(.caption).foregroundStyle(.secondary)
                        Text("Only your Discord friend IDs are sent to your Plaza service for this lookup. It returns current server-visible custom statuses and Playing activity; no messages are read. This Mac remembers each friend’s last visible game for up to two hours after play stops, including across relaunches. Friends do not need Plaza. Click an app to see who played recently, or watch for recent-game bubbles alongside custom statuses. History stays on this Mac and clears when you hide or remove a friend, lose shared-server coverage, unlink Discord, or turn this switch off. During connection gaps, remembered games are marked as recent. Hidden or unobserved activity cannot be recovered.").font(.caption).foregroundStyle(.secondary)
                    }
                    }
                    Section("Discord friends") {
                        Text(social.discordFriendsMessage).font(.callout)
                        DiscordFriendSearchField(query: $friendSearch)
                        Text("\(visibleFriends.count) of \(social.friends.count) friends · Choose a friend to view or assign their Mii.").font(.caption).foregroundStyle(.secondary)
                        ForEach(visibleFriends) { friend in
                            HStack {
                                VStack(alignment: .leading) { Text(friend.displayName); FriendStatusLabel(friend: friend) }
                                Spacer()
                                PlazaButton(friend.temporaryAvatar == true ? "Assign Mii…" : "View Mii") { model.sheet = .friend(friend) }
                                PlazaButton("Hide Mii") { social.hide(friend.id) }
                            }
                        }
                        if visibleFriends.isEmpty && !social.friends.isEmpty {
                            Text("No friends match your search.").font(.callout).foregroundStyle(.secondary)
                        }
                        PlazaButton("Show All Hidden Miis") { social.showAll() }
                    }
                    if social.account != nil {
                    DisclosureGroup("Optional shared Mii profiles & Plaza invitations") {
                    Text("Optional invitations connect Plaza accounts directly. Public Miiverse posts can also reach authorized Discord friends automatically.").font(.caption).foregroundStyle(.secondary)
                    Section("Invite a friend") {
                        HStack {
                            PlazaButton("Create Invitation") { social.createInvite() }.disabled(social.busy)
                            if !social.inviteCode.isEmpty {
                                Text(social.inviteCode).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1)
                                PlazaButton("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(social.inviteCode, forType: .string) }
                            }
                        }
                        Text("Send the code to a friend. It expires after 24 hours and one use; you still approve their request.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            TextField("Friend’s invitation code", text: $friendCode).textFieldStyle(.roundedBorder)
                            PlazaButton("Send Request") { social.requestFriend(friendCode) }.disabled(social.busy || friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if let snapshot = social.snapshot {
                        if !snapshot.incoming.isEmpty {
                            Section("Incoming requests") {
                                ForEach(snapshot.incoming) { request in
                                    HStack { Text(request.displayName); Spacer(); PlazaButton("Accept") { social.accept(request.id) }; PlazaButton("Decline") { social.remove(request.id) } }
                                }
                            }.disabled(social.busy)
                        }
                        if !snapshot.outgoing.isEmpty {
                            Section("Sent requests") {
                                ForEach(snapshot.outgoing) { request in
                                    HStack { Text(request.displayName); Spacer(); Text("Awaiting approval").font(.caption).foregroundStyle(.secondary); PlazaButton("Cancel") { social.remove(request.id) } }
                                }
                            }.disabled(social.busy)
                        }
                    }
                    Section("Plaza friends") {
                        ForEach(social.contacts) { contact in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(contact.displayName)
                                    if let friend = social.friends.first(where: { $0.id == contact.id }) { FriendStatusLabel(friend: friend) }
                                    else { Text("Mii hidden").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                PlazaButton("Remove") { social.remove(contact.id) }
                                PlazaButton("Block") { social.remove(contact.id, block: true) }
                            }
                        }
                        if social.contacts.isEmpty { Text("Accepted friends will appear here once you exchange invitations.").font(.caption).foregroundStyle(.secondary) }
                        PlazaButton("Show All Hidden Miis") { social.showAll() }
                        DisclosureGroup("Blocked accounts", isExpanded: $showBlocks) {
                            ForEach(social.blocks) { blocked in
                                HStack { Text(blocked.displayName); Spacer(); PlazaButton("Unblock") { social.unblock(blocked.id) } }
                            }
                            if social.blocks.isEmpty { Text("No blocked accounts.").font(.caption).foregroundStyle(.secondary) }
                        }.onChange(of: showBlocks) { _, value in if value { social.loadBlocks() } }
                    }.disabled(social.busy)
                    }
                }
                    }
            }.formStyle(.grouped)
        }.frame(width: 680, height: 760)
        .onAppear { restoreDraft() }
        .onChange(of: social.account?.id) { _, _ in restoreDraft() }
        .confirmationDialog("Unlink Discord and delete your shared account?", isPresented: $confirmUnlink, titleVisibility: .visible) {
            PlazaButton("Delete Shared Account", role: .destructive) { social.unlink() }
        } message: { Text("This removes your published Mii, Plaza note, and friendships from the service. Your local characters and Miiverse posts remain on this Mac.") }
    }
    private func restoreDraft() {
        selected = model.document.avatars.first(where: { $0.id == social.linkedAvatarID })?.id ?? model.document.primaryAvatarID ?? model.document.avatars.first?.id
        note = social.account?.note ?? ""; sharing = social.account?.sharing ?? false
        sharePresence = social.account?.sharePresence ?? false
        shareActivity = social.account?.shareActivity ?? false
        shareDiscordFriends = social.account?.shareDiscordFriends ?? false
    }
}

struct FriendProfileView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    let initial: SharedMii
    @Environment(\.dismiss) private var dismiss
    private var friend: SharedMii? { social.friends.first(where: { $0.id == initial.id }) }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: initial.displayName, subtitle: social.previewing ? "Sample friend · preview only" : "Your Plaza friend") { dismiss() }
            ScrollView {
            VStack(spacing: 18) {
            if let friend {
                CharacterPreview(avatar: friend.avatar, angle: 0, pose: 3).frame(height: 230)
                FriendStatusLabel(friend: friend)
                if let status = friend.customStatus, status.isCurrent {
                    Text(status.text).textSelection(.enabled).multilineTextAlignment(.center).padding(.horizontal, 28)
                }
                if friend.temporaryAvatar == true, friend.discordID != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Mii on this Mac", selection: Binding<UUID?>(
                            get: { social.assignedMiiID(for: friend) },
                            set: { social.assignMii($0, to: friend.id) })) {
                            Text("Random Mii (automatic)").tag(Optional<UUID>.none)
                            ForEach(model.document.avatars) { avatar in Text(avatar.name).tag(Optional(avatar.id)) }
                        }
                        Text(friend.locallyAssignedAvatar == true ? "Assigned on this Mac · Priority in plaza" : "Random Mii for this session")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Your choice is saved for this Discord account on this Mac. Their status and games stay attached. If they share their own linked Mii, it takes over automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                        if model.document.avatars.isEmpty {
                            Text("Create a custom Mii in Mii Maker to add it here.").font(.caption)
                        }
                    }.padding(16).background(PlazaStyle.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }
                ForEach(Array(friend.activities.filter { $0.isRecent() }.enumerated()), id: \.offset) { _, activity in Text(activity.label).font(.caption).foregroundStyle(.secondary) }
                if !friend.note.isEmpty { Text(friend.note).textSelection(.enabled).multilineTextAlignment(.center).padding(.horizontal, 28) }
                HStack {
                    PlazaButton("Hide Mii") { social.hide(friend.id); dismiss() }
                    if !social.previewing, social.contacts.contains(where: { $0.id == friend.id }) {
                        PlazaButton("Remove Friend") { social.remove(friend.id); dismiss() }.disabled(social.busy)
                        PlazaButton("Block", role: .destructive) { social.remove(friend.id, block: true); dismiss() }.disabled(social.busy)
                    }
                }
            } else { Text("This Mii is no longer shared with you.").foregroundStyle(.secondary) }
            Spacer(minLength: 12)
            }.padding(.vertical, 18)
            }
        }.frame(width: 560, height: 660).background(PlazaStyle.paper)
    }
}

struct SocialFriendList: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    @State private var friendSearch = ""
    private var visibleFriends: [SharedMii] { matchingFriends(social.friends, query: friendSearch) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(social.previewing ? "SAMPLE PLAZA FRIENDS" : "PLAZA FRIENDS").font(.caption).foregroundStyle(.secondary)
                Spacer(); PlazaButton("Discord & Friends") { model.sheet = .social }
            }.padding(.top, 12)
            if !model.document.preferences.privatePresentation {
                DiscordFriendSearchField(query: $friendSearch)
                Text("\(visibleFriends.count) of \(social.friends.count) friends").font(.caption).foregroundStyle(.secondary)
                ForEach(visibleFriends) { friend in
                    PlazaButton { model.sheet = .friend(friend) } label: {
                        HStack(spacing: 12) {
                            AvatarPortrait(avatar: friend.avatar).frame(width: 36, height: 45)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(friend.displayName).font(.headline)
                                FriendStatusLabel(friend: friend)
                                if let status = friend.customStatus, status.isCurrent { Text(status.text).font(.callout).lineLimit(3) }
                                if let activity = friend.activities.first(where: { $0.isRecent() }) { Text(activity.label).font(.caption).foregroundStyle(.secondary) }
                                if !friend.note.isEmpty { Text(friend.note).font(.callout).lineLimit(3) }
                            }
                            Spacer()
                        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                if social.friends.isEmpty { Text("Connect Discord and load your friends to see their Miis and availability automatically.").font(.callout).foregroundStyle(.secondary) }
                else if visibleFriends.isEmpty { Text("No friends match your search.").font(.callout).foregroundStyle(.secondary) }
            } else { Text("Friend details are hidden in private presentation.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
