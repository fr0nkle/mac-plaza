import XCTest
import AppKit
import SwiftUI
import PlazaCore
@testable import MacPlaza

@MainActor
final class SocialPresentationTests: XCTestCase {
    func testLocalMiiChoicePersistenceIsScopedToViewerAndCanBeCleared() throws {
        let suite = "MacPlaza-MiiChoice-Test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = LocalFriendMiiChoices(defaults: defaults), mii = UUID()
        first.useAccount("123"); first.set(mii, for: "456")
        let reopened = LocalFriendMiiChoices(defaults: defaults)
        reopened.useAccount("123"); XCTAssertEqual(reopened.choices["456"], mii)
        reopened.useAccount("789"); XCTAssertTrue(reopened.choices.isEmpty)
        reopened.useAccount(nil); XCTAssertTrue(reopened.choices.isEmpty)
        reopened.useAccount("123"); XCTAssertEqual(reopened.choices["456"], mii)
        reopened.set(nil, for: "456")
        first.useAccount(nil); first.useAccount("123"); XCTAssertTrue(first.choices.isEmpty)
        defaults.set(["bad": mii.uuidString, "456": "not a uuid", "999": mii.uuidString], forKey: "social.friend-miis.789")
        first.useAccount("789"); XCTAssertEqual(first.choices, ["999": mii])
    }

    func testLocalMiiChoiceFollowsLibraryEditsAndPreservesFriendActivity() throws {
        let social = SocialController(isolated: true)
        var custom = Avatar(name: "Custom", outfit: 8); custom.hair = 44
        social.setLocalMiis([custom]); social.preview()
        let original = try XCTUnwrap(social.friends.last)
        social.assignMii(UUID(), to: original.id)
        XCTAssertNil(social.assignedMiiID(for: original))
        social.assignMii(custom.id, to: social.friends[0].id)
        XCTAssertNil(social.friends[0].locallyAssignedAvatar)
        social.assignMii(custom.id, to: original.id)
        let assigned = try XCTUnwrap(social.friends.last)
        XCTAssertEqual(social.assignedMiiID(for: assigned), custom.id)
        XCTAssertEqual(assigned.locallyAssignedAvatar, true)
        XCTAssertEqual(assigned.avatar.id, original.avatar.id)
        XCTAssertEqual(assigned.avatar.hair, custom.hair)
        XCTAssertEqual(assigned.activities, original.activities)
        XCTAssertEqual(assigned.overheadText, original.overheadText)
        XCTAssertEqual(FriendMiiAssignments.plazaFriends(social.friends, capacity: 1).first?.id, original.id)
        custom.hair = 12; social.setLocalMiis([custom])
        XCTAssertEqual(social.friends.last?.avatar.hair, 12)
        social.setLocalMiis([])
        XCTAssertNil(social.assignedMiiID(for: assigned))
        XCTAssertEqual(social.friends.last?.avatar, original.avatar)
        social.setLocalMiis([custom])
        XCTAssertEqual(social.friends.last?.locallyAssignedAvatar, true)
        social.assignMii(nil, to: original.id)
        XCTAssertEqual(social.friends.last?.avatar, original.avatar)
        XCTAssertEqual(social.friends.last?.locallyAssignedAvatar, false)
        XCTAssertEqual(FriendMiiAssignments.plazaFriends(social.friends, capacity: 1).first?.id, social.friends.first?.id)
    }

    func testPreviewRendersNativeSettingsAndFollowingNotes() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_SOCIAL_QA"] == "1" else { throw XCTSkip("Set PLAZA_SOCIAL_QA=1 for social visual QA.") }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPlaza-Social-QA-" + UUID().uuidString)
        let model = PlazaModel(directory: directory)
        for _ in 0..<100 where !model.loaded { try await Task.sleep(for: .milliseconds(30)) }
        XCTAssertTrue(model.loaded)
        model.social.preview()
        // Card rendering is independent of the staggered plaza entrance.
        model.scene.finishEntrance()
        model.advanceBubblePresentation(by: 36)
        model.document.preferences.pausePosts = true
        model.windowVisible = true
        model.advanceBubblePresentation(by: 36.5)
        XCTAssertEqual(model.postPresentation, .friends)
        model.holdBubble(9, held: true) // Keep the friend-post interval open for this fixture.
        let host = NSHostingView(rootView: PlazaView(model: model))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        defer { model.scene.setMoving(false); window.close() }
        try await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        func noteLayer(_ view: NSView) -> FriendNotesView? {
            if let notes = view as? FriendNotesView { return notes }
            return view.subviews.compactMap(noteLayer).first
        }
        let notes = try XCTUnwrap(noteLayer(host))
        // The FFL renderer loads local assets asynchronously, especially when
        // another Plaza instance is already using the GPU during visual QA.
        for _ in 0..<200 where notes.visibleCardCount == 0 {
            try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(notes.visibleCardCount, 0, "At least one friend note must be visible in the sample plaza.")
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ view: NSView, _ name: String) throws {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
        }
        try capture(host, "discord-friend-plaza.png")
        for friend in model.social.friends.filter({ $0.temporaryAvatar != true }) { model.social.hide(friend.id) }
        model.scene.setMoving(true)
        // Rebuilding the roster retargets walkers; allow the head to clear nearby controls.
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
            if noteLayer(host)?.visibleCardCount ?? 0 > 0 { break }
        }
        XCTAssertEqual(model.social.friends.count, 1)
        XCTAssertEqual(model.social.friends.first?.temporaryAvatar, true)
        XCTAssertGreaterThan(try XCTUnwrap(noteLayer(host)).visibleCardCount, 0,
                             "A friend without a published Mii must still have an overhead activity card.")
        try await Task.sleep(for: .seconds(1))
        try capture(host, "discord-temporary-friend-plaza.png")
        // A Discord roster may exceed the crowd population. Off-scene friends
        // must not displace the visible friend's status card from the cycle.
        let visibleFriend = try XCTUnwrap(model.social.friends.first)
        let offScene = (0..<224).map { index in
            SharedMii(id: UUID().uuidString, displayName: "Off-scene \(index)", avatar: Avatar(),
                      note: "Off-scene note", presence: .online, plazaOnline: false)
        }
        notes.configure(scene: model.scene, friends: offScene + [visibleFriend], paused: true,
                        largerText: false, islands: [], reserved: [], onSelect: { _ in })
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThan(notes.visibleCardCount, 0, "Large friend lists must keep cycling through rendered Miis.")
        var playingFriend = visibleFriend
        playingFriend.activities = [DiscordGameRecord(discordID: "123", name: "Sample Game", observedAt: Date().timeIntervalSince1970).activity]
        XCTAssertEqual(playingFriend.overheadText, "Playing Sample Game")
        notes.configure(scene: model.scene, friends: [playingFriend], paused: true,
                        largerText: false, islands: [], reserved: [], onSelect: { _ in })
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(notes.visibleCardCount, 0, "Current Discord game activity must render on a temporary Mii.")
        try capture(notes, "discord-playing-preview.png")
        playingFriend.customStatus = DiscordCustomStatusRecord(discordID: "123", text: "☀️ Making something nice", observedAt: Date().timeIntervalSince1970)
        XCTAssertEqual(playingFriend.overheadText, "☀️ Making something nice")
        notes.configure(scene: model.scene, friends: [playingFriend], paused: true,
                        largerText: false, islands: [], reserved: [], onSelect: { _ in })
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(notes.visibleCardCount, 0, "A visible custom status must render on a temporary Mii.")
        try capture(notes, "discord-custom-status-preview.png")
        let customMii = try XCTUnwrap(model.document.avatars.first)
        model.social.assignMii(customMii.id, to: visibleFriend.id)
        let profile = NSHostingView(rootView: FriendProfileView(model: model, social: model.social, initial: visibleFriend))
        profile.frame = CGRect(x: 0, y: 0, width: 560, height: 660)
        window.contentView = profile; window.setContentSize(profile.frame.size)
        try await Task.sleep(for: .seconds(1)); profile.layoutSubtreeIfNeeded()
        try capture(profile, "discord-mii-assignment.png")
        XCTAssertEqual(model.social.assignedMiiID(for: visibleFriend), customMii.id)
        model.social.endPreview()
        let panel = NSHostingView(rootView: SocialSettingsView(model: model, social: model.social))
        panel.frame = CGRect(x: 0, y: 0, width: 680, height: 760)
        window.contentView = panel; window.setContentSize(panel.frame.size)
        try await Task.sleep(for: .milliseconds(300)); panel.layoutSubtreeIfNeeded()
        try capture(panel, "discord-settings.png")
    }
    func testOverheadCardsAvoidLaunchControlsJournalAndEachOther() throws {
        let size = CGSize(width: 1280, height: 650), card = CGSize(width: 215, height: 81)
        let control = CGRect(x: 400, y: 200, width: 150, height: 130)
        let positions = FriendNotePlanner.positions(anchors: [CGPoint(x: 470, y: 320), CGPoint(x: 700, y: 470), CGPoint(x: 720, y: 480), CGPoint(x: 1000, y: 450)],
                                                   size: size, card: card, obstacles: [control])
        XCTAssertEqual(positions.count, 2)
        XCTAssertFalse(positions[0].1.intersects(positions[1].1))
        for (_, rect) in positions { XCTAssertFalse(rect.intersects(control)); XCTAssertTrue(CGRect(origin: .zero, size: size).contains(rect)) }
        XCTAssertTrue(FriendNotePlanner.positions(anchors: [.zero], size: CGSize(width: 200, height: 100), card: card, obstacles: []).isEmpty)
        let topRow = CGRect(x: 0, y: 0, width: size.width, height: 180)
        let nearApp = FriendNotePlanner.positions(anchors: [CGPoint(x: 700, y: 195)], size: size,
                                                 card: card, obstacles: [topRow])
        XCTAssertTrue(nearApp.isEmpty, "When no overhead space is free, hide the post instead of moving it below its Mii.")
    }
    func testSampleFriendsNeverCreateASessionAndCanBeHidden() {
        let social = SocialController(isolated: true)
        social.preview()
        XCTAssertTrue(social.previewing)
        XCTAssertFalse(social.hasSession)
        XCTAssertEqual(social.friends.count, 3)
        XCTAssertEqual(social.friends.filter { $0.temporaryAvatar == true }.count, 1)
        XCTAssertEqual(social.friends.last?.overheadText, "Using Discord")
        XCTAssertNoThrow(try social.friends.forEach { try $0.validate() })
        social.hide(social.friends[0].id)
        XCTAssertEqual(social.friends.count, 2)
        social.endPreview()
        XCTAssertTrue(social.friends.isEmpty)
        XCTAssertFalse(social.previewing)
    }
}
