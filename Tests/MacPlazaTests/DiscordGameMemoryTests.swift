import XCTest
import AppKit
import SwiftUI
import PlazaCore
@testable import MacPlaza

@MainActor
final class DiscordGameMemoryTests: XCTestCase {
    func testHistorySurvivesRelaunchButStaysScopedToAccountAndServiceAndCanBeCleared() throws {
        let suite = "MacPlaza-GameHistory-Test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = DiscordGameHistoryStore(defaults: defaults)
        first.useAccount("456", service: "https://plaza.example")
        let now = Date()
        let friends = [DiscordFriendRecord(discordID: "123", displayName: "Friend", presence: .online)]
        let playing = DiscordGameSnapshot(state: "ready", coveredDiscordIDs: ["123"],
            games: [DiscordGameRecord(discordID: "123", name: "Great Game", observedAt: now.timeIntervalSince1970)])
        _ = try first.update(playing, friends: friends, at: now)
        let reopened = DiscordGameHistoryStore(defaults: defaults)
        reopened.useAccount("456", service: "https://plaza.example")
        XCTAssertEqual(reopened.records(at: now).first?.name, "Great Game")
        XCTAssertEqual(reopened.records(at: now).first?.active, false)
        reopened.useAccount("789", service: "https://plaza.example")
        XCTAssertTrue(reopened.records(at: now).isEmpty)
        reopened.useAccount("456", service: "https://other.example")
        XCTAssertTrue(reopened.records(at: now).isEmpty)
        reopened.useAccount("456", service: "https://plaza.example")
        XCTAssertEqual(reopened.records(at: now).count, 1)
        reopened.forget("123")
        XCTAssertTrue(reopened.records(at: now).isEmpty)
        _ = try reopened.update(playing, friends: friends, at: now)
        reopened.clear(); reopened.useAccount(nil, service: nil)
        reopened.useAccount("456", service: "https://plaza.example")
        XCTAssertTrue(reopened.records(at: now).isEmpty)
        _ = try reopened.update(playing, friends: friends, at: now)
        XCTAssertTrue(reopened.records(at: now.addingTimeInterval(7200)).isEmpty)
        let final = DiscordGameHistoryStore(defaults: defaults)
        final.useAccount("456", service: "https://plaza.example")
        XCTAssertTrue(final.records(at: now).isEmpty, "Expired records must be removed from saved history too")
    }

    func testRecentGameBubblesAlternateWithCustomStatusAndKeepTheFriendIdentity() {
        let now = Date().timeIntervalSince1970
        var friend = SharedMii(id: UUID().uuidString, displayName: "Exotic_Panda", avatar: Avatar(), note: "", presence: .online, plazaOnline: false)
        friend.activities = [DiscordGameRecord(discordID: "123", name: "Great Game", observedAt: now - 300, active: false).activity]
        friend.customStatus = DiscordCustomStatusRecord(discordID: "123", text: "Taking a break", observedAt: now)
        let status = PlazaSpeechPost.friend(friend)
        let recent = PlazaSpeechPost.friend(friend, variation: 1)
        XCTAssertEqual(status.text, "Taking a break")
        XCTAssertEqual(recent.text, "Exotic_Panda was recently playing Great Game")
        XCTAssertEqual(status.id, recent.id)
        XCTAssertEqual(status.speaker.id, recent.speaker.id)
        XCTAssertEqual(PlazaSpeechPost.friend(friend, variation: 2).text, status.text)
        friend.presence = .offline
        XCTAssertEqual(PlazaSpeechPost.friend(friend).text, recent.text)
        friend.activities[0].observedAt = now - 7201
        XCTAssertTrue(friend.overheadTexts.isEmpty)
    }

    func testVisibleBubbleActuallyAlternatesAndKeepsItsHeadAnchor() throws {
        _ = NSApplication.shared
        var friend = SharedMii(id: UUID().uuidString, displayName: "Exotic_Panda", avatar: Avatar(), note: "", presence: .online, plazaOnline: false)
        let now = Date().timeIntervalSince1970
        friend.activities = [DiscordGameRecord(discordID: "123", name: "Great Game", observedAt: now - 300, active: false).activity]
        friend.customStatus = DiscordCustomStatusRecord(discordID: "123", text: "Taking a break", observedAt: now)
        let scene = PlazaScene(size: CGSize(width: 1000, height: 700))
        scene.configure(avatars: [friend.avatar], population: 1, localCount: 0)
        let notes = FriendNotesView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        defer { notes.stop() }
        func configure(_ show: Bool) {
            notes.configure(scene: scene, friends: [friend], paused: false, largerText: false,
                islands: [], reserved: [], showPosts: show, onSelect: { _ in })
            scene.acceptFFLAnchors([[0, 0.5, 0.7]])
        }
        configure(true)
        XCTAssertEqual(notes.visiblePosts.first?.speakerID, friend.avatar.id)
        XCTAssertEqual(notes.subviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }.first, "Exotic_Panda: Taking a break")
        configure(true) // Layout/poll refreshes must not change an open bubble.
        XCTAssertEqual(notes.subviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }.first, "Exotic_Panda: Taking a break")
        configure(false); configure(true)
        XCTAssertEqual(notes.subviews.compactMap { ($0 as? NSButton)?.accessibilityLabel() }.first,
            "Exotic_Panda: Exotic_Panda was recently playing Great Game")
        XCTAssertEqual(notes.visiblePosts.first?.speakerID, friend.avatar.id)
        let post = try XCTUnwrap(notes.visiblePosts.first)
        XCTAssertEqual(post.pointerX, post.head.x, accuracy: 0.01)
        if ProcessInfo.processInfo.environment["PLAZA_GAME_HISTORY_QA"] == "1" {
            let image = try XCTUnwrap(notes.bitmapImageRepForCachingDisplay(in: notes.bounds))
            notes.cacheDisplay(in: notes.bounds, to: image)
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/recent-discord-game-bubble.png")
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: output)
        }
    }

    func testAppActivityPreviewFitsSmallWindowsAndRespectsPrivatePresentation() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_GAME_HISTORY_QA"] == "1" else { throw XCTSkip("Opt-in app activity layout capture") }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacPlaza-Game-Preview-" + UUID().uuidString)
        let model = PlazaModel(directory: directory)
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        let app = AppIsland(label: "Notes", bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app")
        model.document.apps = [app]
        model.document.preferences.rotatingHomeScreen = false
        model.document.preferences.ambientSound = false
        model.social.preview(); model.scene.finishEntrance()
        let visitors = FriendAppVisitor.gathered(around: app.id, apps: model.visibleApps,
            friends: model.social.friends, rendered: Set(model.scene.fflCharacters.map(\.id)))
        XCTAssertEqual(visitors.map(\.friend.displayName), ["Cleo"])
        for (height, hidden) in [(510, false), (340, false), (510, true)] {
            model.document.preferences.privatePresentation = hidden
            let host = NSHostingView(rootView: AppPreviewView(model: model, app: app, close: {}, maximumHeight: CGFloat(height))
                .frame(width: 360).padding(20).background(PlazaStyle.paper))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: height + 40), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            let name = hidden ? "app-friends-private" : "app-friends-\(height)"
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/\(name).png")
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: output)
            window.close()
        }
        model.audio.update(enabled: false, allowPreview: false)
        await model.flush(); try await model.storage.endSession()
        try? FileManager.default.removeItem(at: directory)
    }
}
