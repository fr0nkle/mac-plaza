import SwiftUI
import PlazaCore

struct AppFriendsView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    let app: AppIsland
    let close: () -> Void

    var body: some View {
        if !model.document.preferences.privatePresentation {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let visitors = FriendAppVisitor.gathered(around: app.id, apps: model.visibleApps,
                    friends: social.friends, rendered: Set(model.scene.fflCharacters.map(\.id)), at: timeline.date)
                if !visitors.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider().opacity(0.5)
                        Text("Friends around this app").font(.system(size: 12, weight: .semibold))
                        ForEach(visitors) { visitor in
                            Button {
                                close(); model.openCharacter(visitor.friend.avatar)
                            } label: {
                                HStack(spacing: 10) {
                                    MiiHeadIcon(avatar: visitor.friend.avatar).frame(width: 34, height: 38)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(visitor.friend.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(visitor.detail(at: timeline.date)).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(visitor.friend.displayName), \(visitor.detail(at: timeline.date))")
                                .help("View \(visitor.friend.displayName)’s Mii and activity")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
