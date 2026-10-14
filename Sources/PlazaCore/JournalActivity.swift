import Foundation

public struct JournalActivity: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case like, reply }
    public var id: Int
    public var kind: Kind
    public var actorID: String
    public var actorName: String
    public var author: Avatar?
    public var noteID: UUID
    public var sourceID: UUID?
    public var noteText: String
    public var replyText: String?
    public var topic: SharedNoteTopic?
    public var created: Double
    public var read: Bool
    public func validate() throws {
        guard id > 0, id <= 9_000_000_000_000_000, UUID(uuidString: actorID) != nil,
              (1...80).contains(actorName.count), noteText.count <= 280,
              (replyText?.count ?? 0) <= 280, created.isFinite, created >= 0,
              kind != .reply || replyText != nil else { throw PlazaError.invalid("Invalid note activity.") }
        _ = try author?.validated(); try topic?.validate()
    }
    public var message: String { actorName + (kind == .like ? " liked your note" : " replied to your note") }
}

public struct JournalActivitySnapshot: Codable, Equatable, Sendable {
    public var activities: [JournalActivity]
    public var unreadCount: Int
    public var latestID: Int
    public func validated() throws -> Self {
        guard activities.count <= 200, Set(activities.map(\.id)).count == activities.count,
              unreadCount == activities.filter({ !$0.read }).count,
              latestID == (activities.map(\.id).max() ?? 0) else { throw PlazaError.invalid("Invalid activity inbox.") }
        for activity in activities { try activity.validate() }
        return self
    }
}

/// Delivery cursors are separate from the plaza save and scoped to the account.
/// The first fetch fills the badge without replaying a historical alert storm.
public struct JournalActivityDelivery: Sendable {
    public var deliveredThrough: Int?
    public init(deliveredThrough: Int? = nil) { self.deliveredThrough = deliveredThrough }
    public mutating func newUnread(in snapshot: JournalActivitySnapshot) -> [JournalActivity] {
        let previous = deliveredThrough
        deliveredThrough = max(previous ?? 0, snapshot.latestID)
        guard let previous else { return [] }
        return snapshot.activities.filter { !$0.read && $0.id > previous }.sorted { $0.id < $1.id }
    }
}
