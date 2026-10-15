import XCTest
import AppKit
import SwiftUI
import PlazaCore
@testable import MacPlaza

@MainActor final class MiiverseDesignTests: XCTestCase {
    func testSamplePreviewNeverInventsMiiSpeech() {
        let social = SocialController(isolated: true)
        social.preview()
        XCTAssertFalse(social.friends.isEmpty)
        XCTAssertTrue(social.discordSpeechFriends.isEmpty)
        XCTAssertTrue(social.friends.allSatisfy { social.miiversePosts(for: $0).isEmpty })
        social.endPreview()
        XCTAssertTrue(social.friends.allSatisfy { social.miiversePosts(for: $0).isEmpty })
    }
    func testEmptyPlazaHasNoInventedSpeechAndKeepsAuthoredGuideLikeText() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false); model.scene.setMoving(false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.document.notes.isEmpty)
        XCTAssertNil(model.journalPost())
        XCTAssertTrue(model.journalPosts().isEmpty)
        let author = model.document.primaryAvatar
        let note = LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Make yourself at home. This is my actual post.")
        model.document.notes = [note]
        for index in 0..<12 {
            model.bubbleSelections[0] = index
            XCTAssertEqual(model.journalPost()?.text, note.text)
        }
        XCTAssertEqual(model.journalPosts().map(\.id), [note.id.uuidString])
        XCTAssertEqual(model.document.notes, [note])
        await model.flush(); try await model.storage.endSession()
    }

    func testRenderMiiverseAndBirthdayForVisualReview() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_MIIVERSE_QA"] == "1" else { throw XCTSkip("Opt-in visual review") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false); model.scene.setMoving(false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        model.document.preferences.ambientSound = false
        let author = model.document.primaryAvatar
        model.document.notes = [LocalNote(authorID: author.id, author: author.name, appID: nil, text: "A post from the visual review fixture.")]
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/miiverse-redesign")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture<V: View>(_ view: V, name: String) async throws {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
            host.frame = CGRect(x: 0, y: 0, width: 1100, height: 740)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { window.close() }
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        }
        try await capture(MiiverseView(model: model, initialPage: .communities), name: "communities")
        try await capture(MiiverseView(model: model, initialPage: .feed), name: "activity-feed")
        try await capture(MiiverseView(model: model, initialPage: .user), name: "user-menu")
        let audioFixture = root.appendingPathComponent("Alternate theme QA fixture.wav")
        try PlazaAudio.loop().write(to: audioFixture)
        try model.music.stage(audioFixture, for: .miiverseAlternate)
        // Capture the selection controls independently; leaving User Menu
        // discards an unapplied choice through its normal lifecycle.
        try await capture(MiiverseMusicThemeSettings(model: model).padding(30).background(.white), name: "alternate-theme-selection")
        try model.music.stage(audioFixture, for: .miiverseAlternate)
        model.music.applySelection(for: .miiverseAlternate)
        model.mutate { $0.preferences.miiverseAlternateTheme = true }
        try await capture(MiiverseView(model: model, initialPage: .user), name: "user-menu-alternate-theme")
        try await capture(BirthdayCelebrationView(name: "Alex", reducedMotion: false, elapsed: 2).background(PlazaStyle.paper), name: "birthday")
        try await capture(BirthdayCelebrationView(name: "Alex", reducedMotion: true, elapsed: 2).background(PlazaStyle.paper), name: "birthday-reduced-motion")
        await model.flush(); try await model.storage.endSession()
    }
}
