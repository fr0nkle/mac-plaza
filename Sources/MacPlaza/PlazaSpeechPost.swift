import Foundation
import PlazaCore

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

    static func friend(_ friend: SharedMii, variation: Int = 0) -> Self {
        let texts = friend.overheadTexts
        return Self(id: "friend-" + friend.id, speaker: friend.avatar, name: friend.displayName,
             text: texts.isEmpty ? "" : texts[max(0, variation) % texts.count], destination: .friend(friend.id))
    }
}

extension PlazaModel {
    func journalPost(at offset: Int = 0) -> PlazaSpeechPost {
        let selection = bubbleSelections.indices.contains(offset) ? bubbleSelections[offset] : 0
        return journalPost(selection: selection)
    }

    private func journalPost(selection: Int, sourceNotes: [LocalNote]? = nil) -> PlazaSpeechPost {
        let guides = ["Make yourself at home. Click an app to take a closer look before opening it.",
                      "A thought, a sketch, a little spark. Share a post on Miiverse.",
                      "These visitors live on your Mac. Give your own characters a little personality."]
        let notes = sourceNotes ?? bubbleNotes.filter { note in isOwnNote(note) || homeSharedNotes.contains { $0.id == note.id } }
        let index = max(0, selection) % (notes.count + guides.count)
        if index < notes.count {
            let note = notes[index]
            // Preserve a deleted author's identity so their post cannot attach
            // to another Mii. The overhead layer hides absent speakers.
            var speaker = noteAvatar(note)
            if note.shared != true { speaker.id = note.authorID }
            return PlazaSpeechPost(id: note.id.uuidString, speaker: speaker, name: noteDisplayName(note), text: note.text,
                                   drawing: note.drawing, drawingDescription: note.drawingDescription,
                                   destination: .journal(note.id))
        }
        return PlazaSpeechPost(id: "guide-\(index - notes.count)", speaker: document.primaryAvatar,
                               name: document.primaryAvatar.name, text: guides[index - notes.count], destination: .journal(nil))
    }
    /// Distinct speakers, with extra candidates so the layout can skip a blocked
    /// Mii. Guide messages may use local/decorative Miis; authored notes never do.
    func journalPosts() -> [PlazaSpeechPost] {
        let friendIDs = Set(social.friends.map { $0.avatar.id })
        let rendered = Set(scene.fflCharacters.map(\.id))
        let guides = [document.primaryAvatar] + document.avatars.filter { $0.id != document.primaryAvatar.id } +
            scene.fflCharacters.filter { !friendIDs.contains($0.id) }
        var speakers = Set<UUID>(), result: [PlazaSpeechPost] = []
        let notes = bubbleNotes.filter { note in isOwnNote(note) || homeSharedNotes.contains { $0.id == note.id } }
        let start = bubbleSelections.first ?? 0
        for offset in 0..<(notes.count + 3) {
            let post = journalPost(selection: start + offset, sourceNotes: notes)
            var candidate = post
            if post.id.hasPrefix("guide-") {
                guard let guide = guides.first(where: { rendered.contains($0.id) && !speakers.contains($0.id) }) else { continue }
                candidate = PlazaSpeechPost(id: post.id + "-" + guide.id.uuidString,
                    speaker: guide, name: guide.name, text: post.text, destination: .journal(nil))
            }
            guard rendered.contains(candidate.speaker.id), speakers.insert(candidate.speaker.id).inserted else { continue }
            result.append(candidate)
            if result.count == 6 { break }
        }
        return result
    }

}
