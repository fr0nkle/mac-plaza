import Foundation

/// Portable journal content. Launch paths, bookmarks, drafts and local replies
/// never enter the sharing payload.
public struct SharedJournalNote: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var ownerID: String?
    public var sourceID: UUID?
    public var replies: [SharedJournalReply]?
    public var likeCount: Int?
    public var liked: Bool?
    public var displayName: String?
    public var discordID: String?
    public var author: Avatar
    public var text: String
    public var drawing: [InkStroke]
    public var drawingDescription: String
    public var created: Double
    public var topic: SharedNoteTopic?
    public var publicDisplayName: String { displayName ?? author.name }

    public static func publishing(notes: [LocalNote], apps: [AppIsland], primary: Avatar) -> [Self] {
        notes.filter { $0.shared == true }.compactMap { note in
            let app = note.appID.flatMap { id in apps.first { $0.id == id } }
            guard note.appID == nil || app != nil else { return nil }
            return Self(note: note, author: primary, app: app)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public init(note: LocalNote, author: Avatar, app: AppIsland?) {
        id = note.id; self.author = author
        self.author.features.creator = ""; self.author.features.birthDay = 0; self.author.features.birthMonth = 0
        text = note.text; drawing = note.drawing; drawingDescription = note.drawingDescription
        created = note.created.timeIntervalSince1970
        topic = app.map(SharedNoteTopic.init)
    }
    public func validate() throws {
        _ = try author.validated()
        guard displayName.map({ (1...80).contains($0.count) }) ?? true else { throw PlazaError.invalid("Invalid public note name.") }
        guard discordID.map({ $0.count <= 24 && (UInt64($0) ?? 0) > 0 }) ?? true else { throw PlazaError.invalid("Invalid public Discord identity.") }
        guard created.isFinite, created >= 0, ownerID.map({ UUID(uuidString: $0) != nil }) ?? true else {
            throw PlazaError.invalid("Invalid shared note identity or date.")
        }
        guard (0...10000).contains(likeCount ?? 0), (replies?.count ?? 0) <= 50,
              Set((replies ?? []).map(\.id)).count == (replies?.count ?? 0) else {
            throw PlazaError.invalid("Invalid shared note interactions.")
        }
        for reply in replies ?? [] { try reply.validate() }
        try topic?.validate()
        var doc = PlazaDocument(); doc.avatars = [author]; doc.primaryAvatarID = author.id
        doc.notes = [localNote(apps: [])]
        _ = try doc.validated()
    }
    public func localNote(apps: [AppIsland]) -> LocalNote {
        var note = LocalNote(authorID: author.id, author: String(publicDisplayName.prefix(24)),
            appID: topic?.match(in: apps)?.id, text: text, drawing: drawing, drawingDescription: drawingDescription)
        note.id = id; note.created = Date(timeIntervalSince1970: created); note.shared = true
        return note
    }
}

public struct SharedNoteTopic: Codable, Equatable, Sendable {
    public var label: String
    public var bundleID: String
    public var steamAppID: UInt32?
    public init(_ app: AppIsland) { label = app.label; bundleID = app.bundleID; steamAppID = app.steamAppID }
    public func validate() throws {
        guard (1...60).contains(label.count), (1...250).contains(bundleID.count),
              steamAppID.map({ $0 > 0 }) ?? true else { throw PlazaError.invalid("Invalid shared note game.") }
    }
    public func match(in apps: [AppIsland]) -> AppIsland? {
        if let steamAppID { return apps.first { $0.steamAppID == steamAppID } }
        return apps.first { $0.steamAppID == nil && $0.bundleID == bundleID }
    }
}

public struct SharedJournalSnapshot: Codable, Sendable {
    public var notes: [SharedJournalNote]
    public func validated() throws -> Self {
        guard notes.count <= 300, Set(notes.map(\.id)).count == notes.count,
              notes.reduce(0, { $0 + $1.drawing.reduce(0, { $0 + $1.points.count }) }) <= 60000,
              notes.reduce(0, { $0 + ($1.replies?.count ?? 0) }) <= 2000 else {
            throw PlazaError.invalid("Excessive shared notes.")
        }
        for note in notes { try note.validate() }
        return self
    }
}


public struct SharedJournalReply: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var ownerID: String
    public var author: Avatar
    public var text: String
    public var created: Double
    public var displayName: String? = nil
    public var publicDisplayName: String { displayName ?? author.name }
    public func validate() throws {
        _ = try author.validated()
        guard displayName.map({ (1...80).contains($0.count) }) ?? true else { throw PlazaError.invalid("Invalid public reply name.") }
        guard UUID(uuidString: ownerID) != nil, created.isFinite, created >= 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 280 else {
            throw PlazaError.invalid("Invalid shared reply.")
        }
    }
}
