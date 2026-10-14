import SwiftUI
import PlazaCore

struct SharedNoteInteractions: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    let note: LocalNote
    var showReplies = true
    @State private var replying = false
    @State private var editing: SharedJournalReply?
    @State private var error: String?
    private var thread: SharedJournalNote? { model.sharedThread(for: note) }
    private var busy: Bool { thread.map { model.social.interactingNotes.contains($0.id) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PlazaButton {
                    guard let thread else { return }
                    Task {
                        if !(await model.social.like(noteID: thread.id, liked: !(thread.liked ?? false))) {
                            error = model.social.journalInteractionMessage
                        } else { error = nil }
                    }
                } label: {
                    Label("\(thread?.liked == true ? "Liked" : "Like") (\(thread?.likeCount ?? 0))",
                          systemImage: thread?.liked == true ? "heart.fill" : "heart")
                }.foregroundStyle(thread?.liked == true ? Color.pink : PlazaStyle.teal)
                PlazaButton("\(showReplies ? "Reply" : "Replies") (\(thread?.replies?.count ?? 0))") {
                    if showReplies { replying = true } else { model.openMiiverse(note: note.id) }
                }
                    .disabled((thread?.replies?.count ?? 0) >= 50)
                Spacer()
                if thread == nil { Text(model.social.connected ? "Syncing public thread…" : "Connect to Plaza to interact").foregroundStyle(.secondary) }
            }.font(.caption).buttonStyle(.borderless).disabled(thread == nil || busy)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if social.pendingInteractionCount > 0 {
                Text("Saved on this Mac · \(social.pendingInteractionCount) change(s) waiting for delivery.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !social.connected, thread != nil {
                Text("Saved discussion · likes and replies will queue on this Mac.").font(.caption).foregroundStyle(.secondary)
            }
            if showReplies {
            ForEach(thread?.replies ?? []) { reply in
                HStack(alignment: .top, spacing: 10) {
                    MiiHeadIcon(avatar: reply.author).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(reply.publicDisplayName) · Shared reply").font(.caption).foregroundStyle(PlazaStyle.teal)
                        Text(reply.text).font(.callout).textSelection(.enabled)
                    }
                    Spacer()
                    if reply.ownerID == model.social.account?.id {
                        PlazaButton("Edit") { editing = reply }.disabled(busy)
                    }
                    if reply.ownerID == model.social.account?.id || model.isOwnNote(note) {
                        PlazaButton(role: .destructive) {
                            guard let thread else { return }
                            Task {
                                if !(await model.social.deleteReply(noteID: thread.id, replyID: reply.id)) {
                                    error = model.social.journalInteractionMessage
                                } else { error = nil }
                            }
                        } label: { Image(systemName: "trash") }
                        .disabled(busy).accessibilityLabel("Delete shared reply by \(reply.publicDisplayName)")
                    }
                }.font(.caption).buttonStyle(.borderless).padding(12).modifier(PlazaPostSurface())
            }
            }
        }
        .sheet(isPresented: $replying) { ReplyComposer(model: model, noteID: note.id) }
        .sheet(item: $editing) { reply in ReplyComposer(model: model, noteID: note.id, existingSharedReply: reply) }
    }
}
