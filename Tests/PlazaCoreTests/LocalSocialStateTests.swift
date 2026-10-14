import XCTest
@testable import PlazaCore

final class LocalSocialStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture() -> LocalSocialState {
        let owner = UUID().uuidString, author = Avatar(name: "Friend")
        var note = LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Hello")
        note.created = now.addingTimeInterval(-60)
        var shared = SharedJournalNote(note: note, author: author, app: nil)
        shared.ownerID = owner; shared.replies = []; shared.likeCount = 2; shared.liked = false
        var state = LocalSocialState(accountID: UUID().uuidString); state.notes = [shared]
        return state
    }
    private func like(_ state: LocalSocialState, _ value: Bool) -> PendingJournalInteraction {
        PendingJournalInteraction(noteID: state.notes[0].id, liked: value, created: now.timeIntervalSince1970,
            expiresAt: state.notes[0].created + 7 * 86400)
    }
    func testOfflineLikesCoalesceAndSurviveRestartWithoutInflatingCount() throws {
        var state = fixture()
        try state.enqueue(like(state, true)); try state.enqueue(like(state, true))
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.displayedNotes[0].likeCount, 3)
        state = try JSONDecoder().decode(LocalSocialState.self, from: JSONEncoder().encode(state)).validated()
        XCTAssertTrue(state.displayedNotes[0].liked ?? false)
        try state.enqueue(like(state, false))
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.displayedNotes[0].likeCount, 2)
    }
    func testLateAcknowledgementCannotLoseNewerLikeOrReplyEdit() throws {
        var state = fixture()
        let old = like(state, true); try state.enqueue(old)
        let newest = like(state, false); try state.enqueue(newest)
        state.commit(old)
        XCTAssertEqual(state.pending.map(\.id), [newest.id])
        XCTAssertEqual(state.displayedNotes[0].likeCount, 2)
        let replyID = UUID(), author = Avatar(name: "Me")
        let original = PendingJournalInteraction(noteID: state.notes[0].id, replyID: replyID, author: author, text: "First",
            created: now.timeIntervalSince1970, expiresAt: state.notes[0].created + 7 * 86400)
        try state.enqueue(original)
        var edit = original; edit.id = UUID(); edit.text = "Edited"; try state.enqueue(edit)
        state.commit(original)
        XCTAssertEqual(state.displayedNotes[0].replies?.count, 1)
        XCTAssertEqual(state.displayedNotes[0].replies?.first?.id, replyID)
        XCTAssertEqual(state.displayedNotes[0].replies?.first?.text, "Edited")
        XCTAssertTrue(state.pending.contains { $0.id == edit.id })
    }
    func testReplyDeleteRemainsDeletedAfterLostResponseAndRestart() throws {
        var state = fixture(); let author = Avatar(name: "Me"), replyID = UUID()
        let add = PendingJournalInteraction(noteID: state.notes[0].id, replyID: replyID, author: author, text: "Reply",
            created: now.timeIntervalSince1970, expiresAt: state.notes[0].created + 7 * 86400)
        try state.enqueue(add); state.commit(add)
        let remove = PendingJournalInteraction(noteID: state.notes[0].id, replyID: replyID,
            created: now.timeIntervalSince1970, expiresAt: state.notes[0].created + 7 * 86400)
        try state.enqueue(remove)
        let restarted = try JSONDecoder().decode(LocalSocialState.self, from: JSONEncoder().encode(state)).validated()
        XCTAssertTrue(restarted.displayedNotes[0].replies?.isEmpty ?? false)
        XCTAssertEqual(restarted.pending[0].replyID, replyID)
    }
    func testExpiredNotesAndTheirPendingInteractionsArePruned() throws {
        var state = fixture(); try state.enqueue(like(state, true))
        state.prune(now: now.addingTimeInterval(7 * 86400))
        XCTAssertTrue(state.notes.isEmpty); XCTAssertTrue(state.pending.isEmpty)
    }
    func testMalformedQueuesAndCrossAccountSnapshotsAreRejected() throws {
        var state = fixture(), invalid = like(state, true)
        invalid.replyID = UUID(); XCTAssertThrowsError(try state.enqueue(invalid))
        invalid = like(state, true); invalid.expiresAt = .infinity
        XCTAssertThrowsError(try state.enqueue(invalid))
        state.snapshot = SocialSnapshot(account: SocialAccount(id: UUID().uuidString, displayName: "Other", note: "", sharing: false,
            sharePresence: false, shareActivity: false), friends: [], contacts: [], incoming: [], outgoing: [])
        XCTAssertThrowsError(try state.validated())
    }
}
