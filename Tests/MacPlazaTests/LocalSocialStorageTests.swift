import XCTest
import CryptoKit
@testable import MacPlaza
@testable import PlazaCore

final class LocalSocialStorageTests: XCTestCase {
    func testEncryptedQueueSurvivesRestartAndCannotBeMovedToAnotherAccountOrOrigin() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = LocalSocialStore(directory: directory, keyProvider: { _, _ in key })
        let endpoint = URL(string: "https://sharing.example")!, accountID = UUID().uuidString
        var state = LocalSocialState(accountID: accountID)
        let author = Avatar(name: "Author")
        let note = SharedJournalNote(note: LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Private cached discussion"), author: author, app: nil)
        state.notes = [note]
        try state.enqueue(PendingJournalInteraction(noteID: note.id, liked: true, expiresAt: note.created + 7 * 86400))
        try store.save(state, endpoint: endpoint)
        let restarted = LocalSocialStore(directory: directory, keyProvider: { _, _ in key })
        XCTAssertEqual(try restarted.load(endpoint: endpoint, accountID: accountID).pending, state.pending)
        let file = directory.appendingPathComponent(LocalSocialStore.scope(endpoint: endpoint, accountID: accountID) + ".sealed")
        let encrypted = try Data(contentsOf: file)
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("Private cached discussion"))
        let otherAccount = UUID().uuidString
        let otherFile = directory.appendingPathComponent(LocalSocialStore.scope(endpoint: endpoint, accountID: otherAccount) + ".sealed")
        try encrypted.write(to: otherFile)
        XCTAssertThrowsError(try restarted.load(endpoint: endpoint, accountID: otherAccount))
        let otherOrigin = URL(string: "https://other.example")!
        try encrypted.write(to: directory.appendingPathComponent(LocalSocialStore.scope(endpoint: otherOrigin, accountID: accountID) + ".sealed"))
        XCTAssertThrowsError(try restarted.load(endpoint: otherOrigin, accountID: accountID))
        var tampered = encrypted; tampered[tampered.count / 2] ^= 1; try tampered.write(to: file)
        XCTAssertThrowsError(try restarted.load(endpoint: endpoint, accountID: accountID))
    }
}
