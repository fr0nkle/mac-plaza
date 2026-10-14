import XCTest
@testable import PlazaCore

final class SharedJournalTests: XCTestCase {
    func testPublicPostingUsesPrimaryMiiAndPreservesPrivateNotesAndLongDiscordNames() throws {
        var primary = Avatar(name: "My primary"); primary.hair = 99; primary.features.creator = "Private creator"
        let secondary = Avatar(name: "You")
        let publicNote = LocalNote(authorID: secondary.id, author: secondary.name, appID: nil, text: "Public")
        var privateNote = publicNote; privateNote.id = UUID(); privateNote.shared = false
        let originals = [publicNote, privateNote]
        var shared = try XCTUnwrap(SharedJournalNote.publishing(notes: originals, apps: [], primary: primary).first)
        XCTAssertEqual(shared.author.id, primary.id)
        XCTAssertEqual(shared.author.hair, 99)
        XCTAssertEqual(shared.author.features.creator, "")
        shared.displayName = "My linked Discord name longer than twenty-four characters"
        try shared.validate()
        XCTAssertEqual(shared.publicDisplayName, shared.displayName)
        XCTAssertLessThanOrEqual(shared.localNote(apps: []).author.count, 24)
        let catalog = MiiverseCatalog(notes: [], apps: [], shared: [shared], accountID: UUID().uuidString)
        XCTAssertEqual(catalog.filtered(section: "all", query: "twenty-four", sort: .newest).count, 1)
        XCTAssertEqual(originals[0].authorID, secondary.id)
        XCTAssertEqual(originals[1].shared, false)
        let decoded = try JSONDecoder().decode(SharedJournalNote.self, from: JSONEncoder().encode(shared))
        XCTAssertEqual(decoded.publicDisplayName, shared.displayName)
        shared.displayName = String(repeating: "a", count: 81)
        XCTAssertThrowsError(try shared.validate())
    }
    func testPublicPrimaryReplacesTemporaryVisitorWithoutLosingFriendStatus() {
        let primary = Avatar(name: "Primary")
        var note = SharedJournalNote(note: LocalNote(authorID: primary.id, author: primary.name, appID: nil, text: "Hello"), author: primary, app: nil)
        note.ownerID = UUID().uuidString; note.discordID = "100"; note.displayName = "Discord friend"
        var friend = SharedMii(id: UUID().uuidString, displayName: "Old name", avatar: Avatar(name: "Stand-in"), note: "", presence: .online, plazaOnline: false)
        friend.discordID = "100"; friend.temporaryAvatar = true; friend.locallyAssignedAvatar = true
        friend.activities = [SharedAppActivity(name: "Game", bundleID: nil, source: "discord", active: true, observedAt: Date().timeIntervalSince1970)]
        let updated = PublicNoteIdentity.applying(notes: [note, note], to: [friend])
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].avatar.id, primary.id)
        XCTAssertEqual(updated[0].displayName, "Discord friend")
        XCTAssertEqual(updated[0].activities, friend.activities)
        XCTAssertEqual(updated[0].presence, .online)
        XCTAssertFalse(updated[0].temporaryAvatar ?? true)
        XCTAssertEqual(PublicNoteIdentity.applying(notes: [], to: [friend])[0], friend)
    }
    func testMatchingUsesPortableGameIdentityRatherThanLocalUUIDOrLabel() {
        var sender = AppIsland(label: "Bloons TD6", bundleID: "steam.same-launcher")
        sender.steamAppID = 960090
        var receiver = AppIsland(label: "Renamed Bloons", bundleID: "another.launcher")
        receiver.steamAppID = 960090
        var other = sender; other.id = UUID(); other.steamAppID = 123
        XCTAssertEqual(SharedNoteTopic(sender).match(in: [other, receiver])?.id, receiver.id)
        XCTAssertNil(SharedNoteTopic(sender).match(in: [other]))
        let mac = AppIsland(label: "Browser", bundleID: "com.brave.Browser")
        XCTAssertEqual(SharedNoteTopic(mac).match(in: [AppIsland(label: "Renamed", bundleID: mac.bundleID)])?.bundleID, mac.bundleID)
    }
    func testSharingPreservesDrawingAndDateAndOmitsPrivateMetadataAndReplies() throws {
        var avatar = Avatar(name: "Author", outfit: 0)
        avatar.features.creator = "Private creator"; avatar.features.birthDay = 12; avatar.features.birthMonth = 10
        var note = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "A drawing",
            drawing: [InkStroke(points: [InkPoint(0.4, 0.6)])], drawingDescription: "A dot")
        note.created = Date(timeIntervalSince1970: 1700000000)
        let shared = SharedJournalNote(note: note, author: avatar, app: nil)
        try shared.validate()
        let decoded = try JSONDecoder().decode(SharedJournalNote.self, from: JSONEncoder().encode(shared))
        XCTAssertEqual(decoded.localNote(apps: []).drawing, note.drawing)
        XCTAssertEqual(decoded.localNote(apps: []).created, note.created)
        XCTAssertNil(decoded.topic)
        XCTAssertEqual(decoded.author.features.creator, "")
        XCTAssertEqual(decoded.author.features.birthDay, 0)
        XCTAssertEqual(decoded.author.features.birthMonth, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shared)) as? [String: Any])
        XCTAssertNil(object["replies"]); XCTAssertNil(object["appID"])
    }
    func testLegacyNotesStayPrivateUnlessOwnerMigratesThem() throws {
        let note = LocalNote(authorID: UUID(), author: "You", appID: nil, text: "Legacy")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        object.removeValue(forKey: "shared")
        let old = try JSONDecoder().decode(LocalNote.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.shared)
        XCTAssertEqual(note.shared, true)
    }
    func testMalformedSharedNotesAreRejected() throws {
        let author = Avatar()
        var shared = SharedJournalNote(note: LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Hello"), author: author, app: nil)
        shared.created = .infinity
        XCTAssertThrowsError(try shared.validate())
        shared.created = 1; shared.text = String(repeating: "a", count: 281)
        XCTAssertThrowsError(try shared.validate())
    }
    func testSharedThreadRoundTripKeepsInteractionsSeparateFromPrivateLocalReplies() throws {
        let author = Avatar(name: "Reply author", outfit: 4)
        let note = LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Public note")
        var thread = SharedJournalNote(note: note, author: author, app: nil)
        let reply = SharedJournalReply(id: UUID(), ownerID: UUID().uuidString, author: author, text: "Hello friend", created: 1700000000)
        thread.sourceID = note.id; thread.ownerID = UUID().uuidString
        thread.likeCount = 2; thread.liked = true; thread.replies = [reply]
        let decoded = try JSONDecoder().decode(SharedJournalNote.self, from: JSONEncoder().encode(thread))
        try decoded.validate()
        XCTAssertEqual(decoded.sourceID, note.id)
        XCTAssertEqual(decoded.replies, [reply]); XCTAssertEqual(decoded.likeCount, 2); XCTAssertEqual(decoded.liked, true)
        XCTAssertNil(decoded.localNote(apps: []).replies, "Shared discussions must not enter local save/export reply storage")
        XCTAssertFalse(decoded.localNote(apps: []).acknowledged, "Account likes are separate from private appreciation")
    }
    func testSharedInteractionValidationAndOldFeedCompatibility() throws {
        let author = Avatar()
        var thread = SharedJournalNote(note: LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Hello"), author: author, app: nil)
        let old = try JSONDecoder().decode(SharedJournalNote.self, from: JSONEncoder().encode(thread))
        XCTAssertNil(old.replies); XCTAssertNil(old.likeCount); XCTAssertNil(old.sourceID)
        thread.likeCount = 10001
        XCTAssertThrowsError(try thread.validate())
        thread.likeCount = 0
        let reply = SharedJournalReply(id: UUID(), ownerID: UUID().uuidString, author: author, text: "Reply", created: 1)
        thread.replies = [reply, reply]
        XCTAssertThrowsError(try thread.validate())
        var bad = reply; bad.ownerID = "forged identity"
        XCTAssertThrowsError(try bad.validate())
        bad = reply; bad.text = String(repeating: "x", count: 281)
        XCTAssertThrowsError(try bad.validate())
    }

}
