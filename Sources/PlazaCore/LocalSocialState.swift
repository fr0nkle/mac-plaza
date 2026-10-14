import Foundation

/// Device-owned discussion cache and delivery queue. Never included in plaza exports.
public struct LocalSocialState: Codable, Sendable {
    public var accountID: String
    public var snapshot: SocialSnapshot?
    public var notes: [SharedJournalNote] = []
    public var pending: [PendingJournalInteraction] = []
    public var pendingProfile: LocalSharedProfile?
    public var activities: [JournalActivity] = []
    public var readActivityIDs: [Int] = []
    public var updatedAt: Double = 0

    public init(accountID: String) { self.accountID = accountID }

    public func validated() throws -> Self {
        guard UUID(uuidString: accountID) != nil, pending.count <= 200,
              Set(pending.map(\.id)).count == pending.count,
              updatedAt.isFinite, updatedAt >= 0 else { throw PlazaError.invalid("Invalid local sharing state.") }
        _ = try SharedJournalSnapshot(notes: notes).validated()
        if let snapshot {
            _ = try snapshot.validated()
            guard snapshot.account.id == accountID else { throw PlazaError.invalid("Saved account does not match the sharing queue.") }
        }
        for item in pending { try item.validate() }
        try pendingProfile?.validate()
        guard activities.count <= 200, readActivityIDs.count <= 200, readActivityIDs.allSatisfy({ $0 > 0 }),
              Set(readActivityIDs).count == readActivityIDs.count else { throw PlazaError.invalid("Invalid saved activity inbox.") }
        for activity in activities { try activity.validate() }
        return self
    }

    public mutating func prune(now: Date = Date()) {
        notes.removeAll { NoteRetention.isExpired(Date(timeIntervalSince1970: $0.created), now: now) }
        pending.removeAll { $0.expiresAt <= now.timeIntervalSince1970 }
        let ids = Set(notes.map(\.id))
        activities.removeAll { !ids.contains($0.noteID) }
        let activityIDs = Set(activities.map(\.id))
        readActivityIDs.removeAll { !activityIDs.contains($0) }
    }

    public mutating func enqueue(_ item: PendingJournalInteraction) throws {
        try item.validate()
        // Only the latest unsent intention for a like/reply is necessary. A new
        // queue ID ensures an in-flight acknowledgement cannot remove a newer edit.
        var next = pending.filter { $0.noteID != item.noteID || $0.replyID != item.replyID }
        guard next.count < 200 else { throw PlazaError.invalid("The sharing queue is full. Connect to deliver pending changes first.") }
        next.append(item); pending = next
    }

    public mutating func acknowledge(_ id: UUID) { pending.removeAll { $0.id == id } }

    public mutating func commit(_ item: PendingJournalInteraction) {
        var overlay = self; overlay.pending = [item]
        notes = overlay.displayedNotes; acknowledge(item.id)
    }

    public var displayedNotes: [SharedJournalNote] {
        var result = notes
        for item in pending {
            guard let i = result.firstIndex(where: { $0.id == item.noteID }) else { continue }
            if let liked = item.liked {
                let old = result[i].liked ?? false
                result[i].likeCount = max(0, (result[i].likeCount ?? 0) + (liked == old ? 0 : liked ? 1 : -1))
                result[i].liked = liked
            } else if let replyID = item.replyID {
                var replies = result[i].replies ?? []
                let previous = replies.first { $0.id == replyID }
                replies.removeAll { $0.id == replyID }
                if let author = item.author, let text = item.text {
                    replies.append(SharedJournalReply(id: replyID, ownerID: accountID, author: author,
                        text: text, created: previous?.created ?? item.created, displayName: item.displayName))
                }
                result[i].replies = replies.sorted { $0.created < $1.created }
            }
        }
        return result
    }
}

public struct LocalSharedProfile: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var avatar: Avatar
    public var note: String
    public var sharing: Bool
    public var sharePresence: Bool
    public var shareActivity: Bool
    public var shareDiscordFriends: Bool
    public init(avatar: Avatar, note: String, sharing: Bool, sharePresence: Bool, shareActivity: Bool, shareDiscordFriends: Bool) {
        self.avatar = avatar; self.note = note; self.sharing = sharing; self.sharePresence = sharePresence
        self.shareActivity = shareActivity; self.shareDiscordFriends = shareDiscordFriends
    }
    public func validate() throws {
        _ = try avatar.validated()
        guard note.count <= 280 else { throw PlazaError.invalid("Plaza notes support up to 280 characters.") }
    }
}

public struct PendingJournalInteraction: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var noteID: UUID
    public var replyID: UUID?
    public var liked: Bool?
    public var author: Avatar?
    public var text: String?
    public var displayName: String?
    public var created: Double
    public var expiresAt: Double

    public init(noteID: UUID, replyID: UUID? = nil, liked: Bool? = nil, author: Avatar? = nil,
                text: String? = nil, displayName: String? = nil, created: Double = Date().timeIntervalSince1970,
                expiresAt: Double) {
        self.noteID = noteID; self.replyID = replyID; self.liked = liked; self.author = author
        self.text = text; self.displayName = displayName; self.created = created; self.expiresAt = expiresAt
    }

    public func validate() throws {
        guard created.isFinite, created >= 0, expiresAt.isFinite, expiresAt > created,
              expiresAt - created <= 7 * 86400 + 60,
              displayName.map({ (1...80).contains($0.count) }) ?? true else { throw PlazaError.invalid("Invalid queued interaction.") }
        if liked != nil {
            guard replyID == nil, author == nil, text == nil else { throw PlazaError.invalid("Invalid queued like.") }
        } else {
            guard replyID != nil, (author == nil) == (text == nil) else { throw PlazaError.invalid("Invalid queued reply.") }
            if let author, let text {
                _ = try author.validated()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 280 else {
                    throw PlazaError.invalid("Write a reply of up to 280 characters.")
                }
            }
        }
    }
}
