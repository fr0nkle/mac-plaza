import XCTest
@testable import PlazaCore

final class NoteAudienceTests: XCTestCase {
    func testNewPublicDefaultsAndLegacyPrivacyNeverWiden() throws {
        let avatar = Avatar()
        var note = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "New")
        XCTAssertEqual(note.visibility, .everyone)
        XCTAssertEqual(NoteDraft().visibility, .everyone)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as? [String: Any])
        json.removeValue(forKey: "audience")
        let legacyShared = try JSONDecoder().decode(LocalNote.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacyShared.visibility, .friends)
        json.removeValue(forKey: "shared")
        let legacyPrivate = try JSONDecoder().decode(LocalNote.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacyPrivate.visibility, .privateOnly)
        let legacyDraft = try JSONDecoder().decode(NoteDraft.self, from: Data(#"{"text":"Draft","drawing":[],"description":""}"#.utf8))
        XCTAssertEqual(legacyDraft.visibility, .friends)
        note.visibility = .friends
        let restored = try JSONDecoder().decode(LocalNote.self, from: JSONEncoder().encode(note))
        XCTAssertEqual(restored.visibility, .friends)
        note.visibility = .privateOnly
        XCTAssertFalse(note.shared ?? true)
    }
    func testPublishingCarriesPerPostAudienceAndExcludesPrivatePosts() throws {
        let avatar = Avatar()
        let everyone = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "Everyone")
        var friends = everyone; friends.id = UUID(); friends.visibility = .friends
        var secret = everyone; secret.id = UUID(); secret.visibility = .privateOnly
        let payload = SharedJournalNote.publishing(notes: [everyone, friends, secret], apps: [], primary: avatar)
        XCTAssertEqual(Set(payload.compactMap(\.audience)), [.everyone, .friends])
        XCTAssertEqual(payload.count, 2)
        for item in payload {
            try item.validate()
            XCTAssertEqual(item.localNote(apps: []).visibility, item.audience)
        }
        var invalid = payload[0]; invalid.audience = .privateOnly
        XCTAssertThrowsError(try invalid.validate())
    }
    func testPublicStrangersAreDistinctFromFriendsInMiiverse() {
        let avatar = Avatar()
        let own = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "My public post")
        var stranger = SharedJournalNote(note: own, author: avatar, app: nil)
        stranger.id = UUID(); stranger.ownerID = UUID().uuidString; stranger.isFriend = false
        var friend = stranger; friend.id = UUID(); friend.isFriend = true; friend.audience = .friends
        let catalog = MiiverseCatalog(notes: [own], apps: [], shared: [stranger, friend], accountID: UUID().uuidString)
        XCTAssertEqual(Set(catalog.filtered(section: "public", query: "", sort: .newest).map(\.id)), [own.id, stranger.id])
        XCTAssertEqual(catalog.filtered(section: "friends", query: "", sort: .newest).map(\.id), [friend.id])
        XCTAssertEqual(catalog.filtered(section: "all", query: "", sort: .newest).count, 3)
    }
}
