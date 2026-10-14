import XCTest
@testable import PlazaCore

final class NoteRetentionTests: XCTestCase {
    func testExactBoundaryPreservesDraftsCharactersAppsPreferencesAndFreshNotes() throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        var document = PlazaDocument()
        let avatar = document.primaryAvatar
        var old = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "Old public post")
        old.created = now.addingTimeInterval(-NoteRetention.duration)
        var privateNote = old; privateNote.id = UUID(); privateNote.shared = false
        var fresh = old; fresh.id = UUID(); fresh.created = old.created.addingTimeInterval(0.001)
        document.notes = [old, privateNote, fresh]
        var draft = NoteDraft(); draft.text = "Keep this draft"; document.draft = draft
        document.apps = [AppIsland(label: "Game", bundleID: "example.game")]
        let before = document
        XCTAssertEqual(NoteRetention.prune(&document, now: now), 2)
        var expected = before; expected.notes = [fresh]
        XCTAssertEqual(document, expected)
        XCTAssertEqual(NoteRetention.prune(&document, now: now), 0)
    }
    func testExpiredLocalPostsCannotBeRepublished() {
        let avatar = Avatar()
        var note = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "Old")
        note.created = Date().addingTimeInterval(-NoteRetention.duration - 1)
        XCTAssertTrue(SharedJournalNote.publishing(notes: [note], apps: [], primary: avatar).isEmpty)
    }
}
