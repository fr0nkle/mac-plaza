import SwiftUI
import PlazaCore

struct PlazaBottomControls: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    var body: some View {
        VStack(spacing: 8) {
            if let alert = social.activityAlert {
                HStack(alignment: .top, spacing: 8) {
                    Button { social.openActivity(alert) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.document.preferences.privatePresentation ? "New activity on your notes" : alert.message)
                                .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                            Text("View note").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { social.dismissActivityAlert() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss activity alert")
                }.buttonStyle(.plain).padding(12).frame(height: 92)
                    .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
            }
            HStack {
                Spacer()
                Button { model.sheet = .miiverse } label: {
                    Label("Miiverse", systemImage: "bubble.left.and.bubble.right").frame(width: 118, height: 44)
                }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold, design: .rounded))
                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Miiverse").help("Browse your notes and friends’ notes by app and section")
            }
            HStack(spacing: 10) {
                Button { model.sheet = .activity } label: {
                    Label("Activity", systemImage: "bell").frame(width: 152, height: 52)
                }.overlay(alignment: .topTrailing) {
                    if social.unreadActivityCount > 0 {
                        Text(social.unreadActivityCount > 99 ? "99+" : String(social.unreadActivityCount))
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).frame(minWidth: 19, minHeight: 19)
                            .background(Color.red, in: Capsule()).offset(x: -4, y: -4).allowsHitTesting(false)
                    }
                }.accessibilityLabel("Activity, \(social.unreadActivityCount) unread notifications")
                Button { model.sheet = .compose(nil) } label: {
                    Label("Write Note", systemImage: "square.and.pencil").frame(width: 118, height: 52)
                }.disabled(!model.loaded || model.recoveryRequired).accessibilityLabel("Write Note")
            }.font(.system(size: 13, weight: .semibold, design: .rounded)).buttonStyle(.plain)
                .backgroundStyle(.clear)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        }.padding(6).foregroundStyle(PlazaStyle.teal)
    }
}

struct PlazaActivityView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Note activity", subtitle: "Likes and replies from your Plaza friends.") {
                if let onClose { onClose() } else { dismiss() }
            }
            HStack {
                Text("\(social.unreadActivityCount) unread").font(.callout).foregroundStyle(PlazaStyle.teal)
                Spacer()
                Button("Mark all read") { Task { await social.markActivityRead(social.activity.filter { !$0.read }.map(\.id)) } }
                    .disabled(social.unreadActivityCount == 0 || social.markingActivityRead)
                Button("Refresh") { Task { await social.refreshActivity() } }
            }.padding(18)
            ScrollView {
                LazyVStack(spacing: 12) {
                    if social.activity.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bell").font(.system(size: 36)).foregroundStyle(PlazaStyle.teal)
                            Text("You’re all caught up.").font(.title3)
                            Text("When friends like or reply to your public notes, their activity appears here.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(32)
                    }
                    ForEach(social.activity) { entry in
                        Button { social.openActivity(entry) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                if let author = entry.author { MiiHeadIcon(avatar: author).frame(width: 36, height: 36) }
                                else { Image(systemName: entry.kind == .like ? "heart.fill" : "text.bubble").font(.system(size: 24)).frame(width: 36, height: 36).foregroundStyle(PlazaStyle.teal) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.message).font(.system(size: 13, weight: entry.read ? .regular : .semibold))
                                    Text(entry.replyText ?? entry.noteText).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                    Text("\(entry.topic?.label ?? "The plaza") · \(Date(timeIntervalSince1970: entry.created).formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if !entry.read { Circle().fill(PlazaStyle.teal).frame(width: 8, height: 8).accessibilityLabel("Unread") }
                            }.padding(14).modifier(PlazaPostSurface())
                        }.buttonStyle(.plain).accessibilityLabel(entry.message + (entry.read ? ", read" : ", unread"))
                    }
                }.padding(.horizontal, 18).padding(.bottom, 18)
            }
            Divider()
            HStack {
                if social.systemNotificationsEnabled { Label("macOS notifications enabled", systemImage: "bell.badge").font(.caption) }
                else { Button("Enable macOS notifications") { Task { await social.enableActivityNotifications() } } }
                Spacer()
                Text("Activity updates while Mac Plaza is running.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
            if let message = social.activityMessage { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 14) }
        }.frame(width: 660, height: 640).background(PlazaStyle.paper)
        .task { await social.refreshActivity() }
    }
}
