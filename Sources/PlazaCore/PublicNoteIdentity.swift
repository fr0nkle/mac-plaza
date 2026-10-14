import Foundation

public enum PublicNoteIdentity {
    /// An explicitly public note supplies its primary Mii, even when profile sharing is off.
    public static func applying(notes: [SharedJournalNote], to friends: [SharedMii]) -> [SharedMii] {
        let owners = Dictionary(notes.compactMap { note in note.ownerID.map { ($0, note) } }, uniquingKeysWith: { first, _ in first })
        let discord = Dictionary(notes.compactMap { note in note.discordID.map { ($0, note) } }, uniquingKeysWith: { first, _ in first })
        return friends.map { friend in
            guard let note = owners[friend.id] ?? friend.discordID.flatMap({ discord[$0] }) else { return friend }
            var result = friend
            result.avatar = note.author; result.displayName = note.publicDisplayName
            result.temporaryAvatar = false; result.locallyAssignedAvatar = false
            return result
        }
    }
}
