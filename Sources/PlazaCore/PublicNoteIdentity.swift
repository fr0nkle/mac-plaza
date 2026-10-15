import Foundation

public enum PublicNoteIdentity {
    /// Use service ownership or a unique verified Discord link, never names or
    /// an appearance UUID. Conflicting links stay unassigned.
    public static func friend(for note: SharedJournalNote, in friends: [SharedMii]) -> SharedMii? {
        let owners = friends.filter { note.ownerID != nil && identity($0.id) == identity(note.ownerID!) }
        let discord = friends.filter { note.discordID != nil && $0.discordID == note.discordID }
        guard owners.count <= 1, discord.count <= 1 else { return nil }
        if let owner = owners.first {
            if let id = note.discordID, let linked = owner.discordID, id != linked { return nil }
            if let linked = discord.first, identity(linked.id) != identity(owner.id) { return nil }
            return owner
        }
        return discord.first
    }
    public static func hasConflictingFriendIdentity(_ note: SharedJournalNote, in friends: [SharedMii]) -> Bool {
        friend(for: note, in: friends) == nil && friends.contains { candidate in
            note.ownerID.map { identity($0) == identity(candidate.id) } == true ||
                (note.discordID != nil && candidate.discordID == note.discordID)
        }
    }
    private static func identity(_ value: String) -> String { UUID(uuidString: value)?.uuidString ?? value }
    /// An explicitly public note supplies its primary Mii, even when profile sharing is off.
    public static func applying(notes: [SharedJournalNote], to friends: [SharedMii]) -> [SharedMii] {
        var latest: [String: SharedJournalNote] = [:]
        for note in notes.sorted(by: { $0.created > $1.created }) {
            if let owner = Self.friend(for: note, in: friends), latest[owner.id] == nil { latest[owner.id] = note }
        }
        return friends.map { friend in
            guard let note = latest[friend.id] else { return friend }
            var result = friend
            result.avatar = note.author; result.displayName = note.publicDisplayName
            result.temporaryAvatar = false; result.locallyAssignedAvatar = false
            return result
        }
    }
}
