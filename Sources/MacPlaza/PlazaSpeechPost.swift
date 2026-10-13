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
        let guides = ["Make yourself at home. Click an app to take a closer look before opening it.",
                      "A thought, a sketch, a little spark. Leave a note in your journal.",
                      "These visitors live on your Mac. Give your own characters a little personality."]
        let notes = bubbleNotes.filter { note in isOwnNote(note) || homeSharedNotes.contains { $0.id == note.id } }
        let selection = bubbleSelections.indices.contains(offset) ? bubbleSelections[offset] : 0
        let index = max(0, selection) % (notes.count + guides.count)
        if index < notes.count {
            let note = notes[index]
            // Preserve a deleted author's identity so their post cannot attach
            // to another Mii. The overhead layer hides absent speakers.
            var speaker = noteAvatar(note)
            speaker.id = note.authorID
            return PlazaSpeechPost(id: note.id.uuidString, speaker: speaker, name: note.author, text: note.text,
                                   drawing: note.drawing, drawingDescription: note.drawingDescription,
                                   destination: .journal(note.id))
        }
        return PlazaSpeechPost(id: "guide-\(index - notes.count)", speaker: document.primaryAvatar,
                               name: document.primaryAvatar.name, text: guides[index - notes.count], destination: .journal(nil))
    }
}
