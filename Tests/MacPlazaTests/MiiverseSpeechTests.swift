import XCTest
import AppKit
import PlazaCore
@testable import MacPlaza

@MainActor final class MiiverseSpeechTests: XCTestCase {
    private func friend(_ discordID: String = "123") -> SharedMii {
        var friend = SharedMii(id: UUID().uuidString, displayName: "Same name", avatar: Avatar(name: "Same name"),
            note: "Keep this legacy profile note stored", presence: .online, plazaOnline: true)
        friend.discordID = discordID
        return friend
    }
    private func post(_ author: Avatar, owner: String? = nil, discordID: String? = nil) -> SharedJournalNote {
        var post = SharedJournalNote(note: LocalNote(authorID: author.id, author: author.name, appID: nil, text: "An authored Miiverse post"), author: author, app: nil)
        post.ownerID = owner; post.discordID = discordID
        return post
    }
    func testMiiverseOwnershipUsesAccountLinksAndKeepsDrawingsAndPostDestination() throws {
        let linked = friend(), other = friend("456")
        var note = post(Avatar(name: "Old appearance"), owner: linked.id.lowercased(), discordID: "123")
        note.drawing = [InkStroke(points: [InkPoint(0.2, 0.3)])]; note.drawingDescription = "A dot"
        let speech = try XCTUnwrap(PlazaSpeechPost.miiverse(note, friends: [linked, other]))
        XCTAssertEqual(speech.speaker, linked.avatar)
        XCTAssertEqual(speech.drawing, note.drawing)
        XCTAssertEqual(speech.accessibleText, "A dot")
        guard case .journal(let id) = speech.destination else { return XCTFail("A post opens Miiverse") }
        XCTAssertEqual(id, note.id)
        var collision = post(linked.avatar)
        XCTAssertNil(PlazaSpeechPost.miiverse(collision, friends: [linked, other]), "Appearance and matching names cannot assign someone else's post")
        collision.author = Avatar(name: linked.displayName)
        XCTAssertNotEqual(PlazaSpeechPost.miiverse(collision, friends: [linked, other])?.speaker.id, linked.avatar.id)
        var conflict = note; conflict.discordID = other.discordID
        XCTAssertNil(PlazaSpeechPost.miiverse(conflict, friends: [linked, other]))
        XCTAssertNil(PublicNoteIdentity.friend(for: conflict, in: [linked, other]))
        var duplicateLink = other; duplicateLink.discordID = linked.discordID
        XCTAssertNil(PlazaSpeechPost.miiverse(note, friends: [linked, duplicateLink]))
    }
    func testEmptyExpiredAndDrawingOnlyMiiversePosts() throws {
        let linked = friend()
        var note = post(linked.avatar, owner: linked.id)
        note.text = "  \n "
        XCTAssertNil(PlazaSpeechPost.miiverse(note, friends: [linked]))
        note.drawing = [InkStroke(points: [InkPoint(0.4, 0.5)])]
        XCTAssertNotNil(PlazaSpeechPost.miiverse(note, friends: [linked]))
        note.created = Date().addingTimeInterval(-NoteRetention.duration - 1).timeIntervalSince1970
        XCTAssertNil(PlazaSpeechPost.miiverse(note, friends: [linked]))
    }
    func testDiscordSpeechIncludesGeneratedAndAssignedMiisButNeverLegacyNotesOrGenericPresence() throws {
        for assigned in [false, true] {
            var linked = friend(); linked.temporaryAvatar = true; linked.locallyAssignedAvatar = assigned
            let originalNote = linked.note
            XCTAssertNil(PlazaSpeechPost.discord(linked))
            let now = Date().timeIntervalSince1970
            linked.customStatus = DiscordCustomStatusRecord(discordID: "123", text: "Making something nice", observedAt: now)
            linked.activities = [SharedAppActivity(name: "Current Game", bundleID: nil, source: "discord", active: true, observedAt: now),
                SharedAppActivity(name: "Earlier Game", bundleID: nil, source: "discord", active: false, observedAt: now - 300)]
            let status = try XCTUnwrap(PlazaSpeechPost.discord(linked, variation: 0))
            XCTAssertEqual(status.text, "Making something nice")
            XCTAssertEqual(status.speaker, linked.avatar)
            XCTAssertEqual(PlazaSpeechPost.discord(linked, variation: 1)?.text, "Playing Current Game")
            XCTAssertEqual(PlazaSpeechPost.discord(linked, variation: 2)?.text, "Same name was recently playing Earlier Game")
            XCTAssertEqual(PlazaSpeechPost.discord(linked, variation: 3)?.text, status.text)
            guard case .friend(let id) = status.destination else { return XCTFail("Discord speech opens friend details") }
            XCTAssertEqual(id, linked.id)
            linked.avatar = Avatar(name: "New assigned appearance")
            XCTAssertEqual(PlazaSpeechPost.discord(linked)?.speaker, linked.avatar)
            XCTAssertEqual(linked.note, originalNote)
        }
    }
    func testDiscordCardsRotateWithPostsAndClickTheirAccountAcrossAppearanceChanges() throws {
        _ = NSApplication.shared
        var linked = friend(); linked.temporaryAvatar = true; linked.locallyAssignedAvatar = true
        let now = Date().timeIntervalSince1970
        linked.customStatus = DiscordCustomStatusRecord(discordID: "123", text: "A real custom status", observedAt: now)
        linked.activities = [SharedAppActivity(name: "Recent Game", bundleID: nil, source: "discord", active: false, observedAt: now)]
        let scene = PlazaScene(size: CGSize(width: 1000, height: 700))
        scene.configure(avatars: [linked.avatar], population: 1, localCount: 0)
        let view = FriendNotesView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        defer { view.stop() }
        let note = post(linked.avatar, owner: linked.id)
        let journal = try XCTUnwrap(PlazaSpeechPost.miiverse(note, friends: [linked]))
        var clickedFriend: String?, clickedPost: UUID?
        func configure(_ show: Bool) {
            view.configure(scene: scene, friends: [linked], paused: false, largerText: false, islands: [], reserved: [], showPosts: show,
                journalPosts: [journal], onSelectJournal: { clickedPost = $0 }, onSelect: { clickedFriend = $0.id })
            scene.acceptFFLAnchors([[0, 0.5, 0.7]])
        }
        configure(true)
        let button = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(button.accessibilityLabel(), "Same name: A real custom status")
        button.performClick(nil); XCTAssertEqual(clickedFriend, linked.id)
        configure(false)
        XCTAssertEqual(button.accessibilityLabel(), "Same name: An authored Miiverse post")
        button.performClick(nil); XCTAssertEqual(clickedPost, note.id)
        configure(true)
        XCTAssertEqual(button.accessibilityLabel(), "Same name: Same name was recently playing Recent Game")
        XCTAssertEqual(view.visiblePosts.first?.speakerID, linked.avatar.id)
    }

    func testExpiredUnlinkedOrMismatchedDiscordContentCannotSpeak() {
        var linked = friend()
        let now = Date().timeIntervalSince1970
        linked.customStatus = DiscordCustomStatusRecord(discordID: "456", text: "Another account", observedAt: now)
        linked.activities = [SharedAppActivity(name: "Expired Game", bundleID: nil, source: "discord", active: false, observedAt: now - 7201),
            SharedAppActivity(name: "Plaza activity", bundleID: nil, source: "plaza", active: true, observedAt: now)]
        XCTAssertNil(PlazaSpeechPost.discord(linked))
        linked.customStatus = DiscordCustomStatusRecord(discordID: "123", text: "Old status", observedAt: now - 7201)
        XCTAssertNil(PlazaSpeechPost.discord(linked))
        linked.customStatus = DiscordCustomStatusRecord(discordID: "123", text: "Current status", observedAt: now)
        linked.presence = .offline
        XCTAssertNil(PlazaSpeechPost.discord(linked))
        linked.presence = .online; linked.discordID = nil
        XCTAssertNil(PlazaSpeechPost.discord(linked))
    }
}
