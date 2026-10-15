import Foundation
import PlazaCore

extension SocialController {
    var discordSpeechFriends: [SharedMii] {
        guard !previewing, hasSession || hasDiscordFriendsAuthorization else { return [] }
        return friends.filter { ($0.discordID.flatMap(UInt64.init) ?? 0) > 0 }
    }
    func miiversePosts(for friend: SharedMii) -> [SharedJournalNote] {
        guard hasSession, !previewing else { return [] }
        return visibleSharedJournal.filter { PublicNoteIdentity.friend(for: $0, in: friends)?.id == friend.id }
            .sorted { $0.created > $1.created }
    }
}

struct PlazaSpeechPost {
    enum Destination { case journal(UUID?), friend(String) }
    let id: String
    let speaker: Avatar
    let name: String
    let text: String
    var drawing: [InkStroke] = []
    var drawingDescription = ""
    let destination: Destination
    var accessibleText: String { drawing.isEmpty ? text : drawingDescription }

    /// Discord identity belongs to the roster entry, including generated or
    /// manually assigned appearances. The legacy profile note is never read.
    static func discord(_ friend: SharedMii, variation: Int = 0) -> Self? {
        guard let discordID = friend.discordID, (UInt64(discordID) ?? 0) > 0 else { return nil }
        var texts: [String] = []
        if let status = friend.customStatus, status.discordID == discordID,
           status.isCurrent, friend.presence != .offline, friend.presence != .unknown,
           !status.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.append(status.text) }
        for game in friend.activities.filter({ $0.source == "discord" && $0.isRecent() }).sorted(by: {
            if $0.active != $1.active { return $0.active }; return $0.observedAt > $1.observedAt
        }) {
            let text = game.active ? game.label : "\(friend.displayName) was recently playing \(game.name)"
            if !texts.contains(text) { texts.append(text) }
        }
        guard !texts.isEmpty else { return nil }
        let index = max(0, variation) % texts.count
        return Self(id: "discord-" + friend.id + "-" + String(index) + "-" + texts[index],
            speaker: friend.avatar, name: friend.displayName, text: texts[index], destination: .friend(friend.id))
    }

    static func miiverse(_ note: SharedJournalNote, friends: [SharedMii]) -> Self? {
        guard !NoteRetention.isExpired(Date(timeIntervalSince1970: note.created)),
              !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !note.drawing.isEmpty,
              !PublicNoteIdentity.hasConflictingFriendIdentity(note, in: friends) else { return nil }
        let friend = PublicNoteIdentity.friend(for: note, in: friends)
        // An unrelated author cannot borrow a friend's appearance UUID.
        guard friend != nil || !friends.contains(where: { $0.avatar.id == note.author.id }) else { return nil }
        return Self(id: note.id.uuidString, speaker: friend?.avatar ?? note.author, name: note.publicDisplayName,
            text: note.text, drawing: note.drawing, drawingDescription: note.drawingDescription, destination: .journal(note.id))
    }
}

extension PlazaModel {
    func journalPost(at offset: Int = 0) -> PlazaSpeechPost? {
        let selection = bubbleSelections.indices.contains(offset) ? bubbleSelections[offset] : 0
        let notes = authoredBubbleNotes
        guard !notes.isEmpty else { return nil }
        return speechPost(notes[max(0, selection) % notes.count])
    }

    private var authoredBubbleNotes: [LocalNote] {
        bubbleNotes.filter { note in
            (!note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !note.drawing.isEmpty) &&
                (isOwnNote(note) || homeSharedNotes.contains { $0.id == note.id })
        }
    }

    private func speechPost(_ note: LocalNote) -> PlazaSpeechPost? {
        if !isOwnNote(note) {
            guard let shared = homeSharedNotes.first(where: { $0.id == note.id }),
                  !document.avatars.contains(where: { $0.id == shared.author.id }) else { return nil }
            return PlazaSpeechPost.miiverse(shared, friends: social.friends)
        }
        // A deleted author's note must never attach to an unrelated Mii.
        var speaker = noteAvatar(note)
        if note.shared != true { speaker.id = note.authorID }
        return PlazaSpeechPost(id: note.id.uuidString, speaker: speaker, name: noteDisplayName(note), text: note.text,
            drawing: note.drawing, drawingDescription: note.drawingDescription, destination: .journal(note.id))
    }

    /// Only authored content; empty Miis remain silent. One post per speaker.
    func journalPosts() -> [PlazaSpeechPost] {
        let notes = authoredBubbleNotes
        guard !notes.isEmpty else { return [] }
        let rendered = Set(scene.fflCharacters.map(\.id))
        let start = max(0, bubbleSelections.first ?? 0) % notes.count
        var speakers = Set<UUID>(), result: [PlazaSpeechPost] = []
        for offset in 0..<notes.count {
            guard let post = speechPost(notes[(start + offset) % notes.count]) else { continue }
            guard rendered.contains(post.speaker.id), speakers.insert(post.speaker.id).inserted else { continue }
            result.append(post)
            if result.count == 6 { break }
        }
        return result
    }
}
