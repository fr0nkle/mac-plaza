import XCTest
@testable import PlazaCore

final class JournalActivityTests: XCTestCase {
    private func entry(_ id: Int, read: Bool = false) -> JournalActivity {
        JournalActivity(id: id, kind: .like, actorID: UUID().uuidString, actorName: "Friend",
            author: nil, noteID: UUID(), sourceID: UUID(), noteText: "A note", replyText: nil,
            topic: nil, created: 1, read: read)
    }
    private func snapshot(_ entries: [JournalActivity]) -> JournalActivitySnapshot {
        JournalActivitySnapshot(activities: entries, unreadCount: entries.filter { !$0.read }.count,
            latestID: entries.map(\.id).max() ?? 0)
    }
    func testInitialHistoryFillsBadgeWithoutReplayingOldAlerts() throws {
        var delivery = JournalActivityDelivery()
        let old = snapshot([entry(1)])
        _ = try old.validated()
        XCTAssertTrue(delivery.newUnread(in: old).isEmpty)
        let new = entry(2)
        XCTAssertEqual(delivery.newUnread(in: snapshot([new] + old.activities)).map(\.id), [2])
        XCTAssertTrue(delivery.newUnread(in: snapshot([new] + old.activities)).isEmpty)
    }
    func testWithdrawalsAndReadOnAnotherDeviceDoNotRepeatNotifications() {
        var delivery = JournalActivityDelivery()
        _ = delivery.newUnread(in: snapshot([]))
        XCTAssertEqual(delivery.newUnread(in: snapshot([entry(4)])).map(\.id), [4])
        XCTAssertTrue(delivery.newUnread(in: snapshot([])).isEmpty)
        XCTAssertEqual(delivery.deliveredThrough, 4)
        XCTAssertTrue(delivery.newUnread(in: snapshot([entry(5, read: true)])).isEmpty)
        XCTAssertEqual(delivery.newUnread(in: snapshot([entry(6)])).map(\.id), [6])
    }
    func testInboxRejectsMisleadingCountsDuplicateIDsAndInvalidActors() throws {
        let event = entry(1)
        var data = snapshot([event])
        XCTAssertEqual(try JSONDecoder().decode(JournalActivitySnapshot.self, from: JSONEncoder().encode(data)).validated(), data)
        data.unreadCount = 0
        XCTAssertThrowsError(try data.validated())
        data = snapshot([event, event])
        XCTAssertThrowsError(try data.validated())
        var bad = event; bad.actorID = "invalid"
        XCTAssertThrowsError(try bad.validate())
    }
}
