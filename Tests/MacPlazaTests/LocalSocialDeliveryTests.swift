import XCTest
import Foundation
@testable import MacPlaza
@testable import PlazaCore

private final class SharingTransport: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class LocalSocialDeliveryTests: XCTestCase {
    @MainActor
    func testOutageRetainsDiscussionAndReconnectDeliversQueuedLike() async throws {
        let (social, fixture) = try makeClient()
        SharingTransport.handler = { request in try fixture.handle(request) }
        defer { SharingTransport.handler = nil }
        fixture.online = false
        await social.refresh()
        XCTAssertFalse(social.connected); XCTAssertEqual(social.sharedJournal.count, 1)
        let accepted = await social.like(noteID: fixture.note.id, liked: true)
        XCTAssertTrue(accepted); XCTAssertEqual(social.pendingInteractionCount, 1)
        XCTAssertTrue(social.sharedJournal[0].liked ?? false)
        XCTAssertEqual(fixture.likeRequests, 0)
        fixture.online = true
        await social.refresh()
        XCTAssertTrue(social.connected); XCTAssertEqual(social.pendingInteractionCount, 0)
        XCTAssertEqual(fixture.likeRequests, 1); XCTAssertEqual(social.sharedJournal[0].likeCount, 1)
    }
    @MainActor
    func testReplyRetriesUseSameIDAfterCommittedResponseIsLost() async throws {
        let (social, fixture) = try makeClient()
        SharingTransport.handler = { request in try fixture.handle(request) }
        defer { SharingTransport.handler = nil }
        let replyID = UUID()
        let accepted = await social.reply(noteID: fixture.note.id, replyID: replyID, author: Avatar(name: "Me"), text: "Queued reply")
        XCTAssertTrue(accepted)
        fixture.loseReplyResponse = true
        await social.refresh()
        XCTAssertEqual(social.pendingInteractionCount, 1)
        XCTAssertEqual(fixture.note.replies?.count, 1)
        await social.refresh()
        XCTAssertEqual(social.pendingInteractionCount, 0)
        XCTAssertEqual(fixture.replyIDs, [replyID, replyID])
        XCTAssertEqual(social.sharedJournal[0].replies?.count, 1)
    }
    @MainActor
    func testRevokedNoteDiscardsPendingMutationWithoutRestoringIt() async throws {
        let (social, fixture) = try makeClient()
        SharingTransport.handler = { request in try fixture.handle(request) }
        defer { SharingTransport.handler = nil }
        let accepted = await social.like(noteID: fixture.note.id, liked: true)
        XCTAssertTrue(accepted)
        fixture.revoked = true
        await social.refresh()
        XCTAssertEqual(social.pendingInteractionCount, 0); XCTAssertTrue(social.sharedJournal.isEmpty)
        XCTAssertNotNil(social.journalInteractionMessage)
    }
    @MainActor
    private func makeClient() throws -> (SocialController, SharingFixture) {
        let fixture = SharingFixture()
        var state = LocalSocialState(accountID: fixture.accountID)
        state.snapshot = fixture.snapshot; state.notes = [fixture.note]
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SharingTransport.self]
        let social = SocialController(isolated: true, transport: URLSession(configuration: config),
            restoredSession: (URL(string: "https://sharing.example")!, "test-session", state))
        return (social, fixture)
    }
}

private final class SharingFixture {
    var online = true, revoked = false, loseReplyResponse = false
    var likeRequests = 0
    var replyIDs: [UUID] = []
    let accountID = UUID().uuidString
    var note: SharedJournalNote
    var snapshot: SocialSnapshot {
        SocialSnapshot(account: SocialAccount(id: accountID, displayName: "Me", note: "", sharing: false,
            sharePresence: false, shareActivity: false), friends: [], contacts: [], incoming: [], outgoing: [])
    }
    init() {
        let author = Avatar(name: "Friend")
        note = SharedJournalNote(note: LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Cached discussion"), author: author, app: nil)
        note.ownerID = UUID().uuidString; note.replies = []; note.likeCount = 0; note.liked = false
    }
    func handle(_ request: URLRequest) throws -> (Int, Data) {
        guard online else { throw URLError(.notConnectedToInternet) }
        let path = request.url!.path
        if path.hasSuffix("/snapshot") { return (200, try JSONEncoder().encode(snapshot)) }
        if path.hasSuffix("/threads") { return (200, try JSONEncoder().encode(SharedJournalSnapshot(notes: revoked ? [] : [note]))) }
        if path.hasSuffix("/activity") { return (200, Data("{\"activities\":[],\"unreadCount\":0,\"latestID\":0}".utf8)) }
        if path.hasSuffix("/like") {
            if revoked { return (403, Data("{\"error\":\"Note access revoked.\"}".utf8)) }
            likeRequests += 1; note.liked = true; note.likeCount = 1
        }
        if path.contains("/replies/"), let id = UUID(uuidString: request.url!.lastPathComponent) {
            replyIDs.append(id)
            note.replies = [SharedJournalReply(id: id, ownerID: accountID, author: Avatar(name: "Me"), text: "Queued reply", created: Date().timeIntervalSince1970)]
            if loseReplyResponse { loseReplyResponse = false; throw URLError(.networkConnectionLost) }
        }
        return (200, Data("{}".utf8))
    }
}
