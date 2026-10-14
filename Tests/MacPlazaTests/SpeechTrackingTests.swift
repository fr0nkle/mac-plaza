import XCTest
import AppKit
import SwiftUI
import PlazaCore
@testable import MacPlaza

@MainActor
final class SpeechTrackingTests: XCTestCase {
    func testPlacementStaysAboveSpeakerAndTracksWalkingWithoutDetachingPointer() throws {
        let size = CGSize(width: 1280, height: 720), card = CGSize(width: 230, height: 108)
        let head = CGPoint(x: 500, y: 450), nextHead = CGPoint(x: 535, y: 470)
        let first = try XCTUnwrap(FriendNotePlanner.positions(anchors: [head], size: size, card: card, obstacles: [], limit: 1).first?.1)
        let next = try XCTUnwrap(FriendNotePlanner.positions(anchors: [nextHead], size: size, card: card, obstacles: [], limit: 1).first?.1)
        XCTAssertEqual(next.minX - first.minX, 35, accuracy: 0.01)
        XCTAssertEqual(next.minY - first.minY, 20, accuracy: 0.01)
        XCTAssertLessThan(first.maxY, head.y)
        for point in [CGPoint(x: 45, y: 400), CGPoint(x: 1235, y: 400)] {
            let rect = try XCTUnwrap(FriendNotePlanner.positions(anchors: [point], size: size, card: card, obstacles: [], limit: 1).first?.1)
            XCTAssertGreaterThanOrEqual(point.x - rect.minX, 27)
            XCTAssertLessThanOrEqual(point.x - rect.minX, card.width - 27)
        }
        XCTAssertTrue(FriendNotePlanner.positions(anchors: [CGPoint(x: -50, y: 400)], size: size, card: card, obstacles: []).isEmpty)
        XCTAssertTrue(FriendNotePlanner.positions(anchors: [head], size: size, card: card,
                                                obstacles: [CGRect(x: 0, y: 0, width: 1280, height: 450)]).isEmpty)
    }

    func testOneTwoAndThreeBubblesUseDistinctWalkingSpeakersWithoutOverlap() throws {
        let avatars = (0..<4).map { Avatar(name: "Speaker \($0)") }
        let scene = PlazaScene(size: CGSize(width: 1280, height: 720))
        scene.configure(avatars: avatars, population: 4, localCount: 4)
        let view = FriendNotesView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        defer { view.stop() }
        let posts = avatars.enumerated().map { PlazaSpeechPost(id: "post-\($0.offset)", speaker: $0.element,
            name: $0.element.name, text: "Hello", destination: .journal(nil)) }
        let anchors: [[Double]] = [[0,0.2,0.65], [1,0.5,0.65], [2,0.8,0.65], [3,0.5,0.9]]
        for count in 1...3 {
            view.configure(scene: scene, friends: [], paused: false, largerText: false, islands: [], reserved: [],
                showPosts: false, journalPosts: [posts[0]] + posts, maxPosts: count, onSelect: { _ in })
            scene.acceptFFLAnchors(anchors)
            XCTAssertEqual(view.visibleCardCount, count)
            let visible = view.visiblePosts
            XCTAssertEqual(Set(visible.map(\.speakerID)).count, count, "Two posts from one author must share one slot")
            for (i, post) in visible.enumerated() {
                XCTAssertLessThan(post.frame.maxY, post.head.y)
                XCTAssertEqual(post.pointerX, post.head.x, accuracy: 0.01)
                for other in visible.dropFirst(i+1) { XCTAssertFalse(post.frame.intersects(other.frame)) }
            }
        }
        let speakers = Set(view.visiblePosts.map(\.speakerID))
        scene.acceptFFLAnchors(anchors.map { [$0[0],$0[1]+0.02,$0[2]+0.02] })
        XCTAssertEqual(Set(view.visiblePosts.map(\.speakerID)), speakers)
        XCTAssertEqual(view.visibleCardCount, 3)
    }

    func testLateAnchorsCanFillAllThreeSlots() {
        let avatars = (0..<3).map { Avatar(name: "Speaker \($0)") }
        let scene = PlazaScene(size: CGSize(width: 1280, height: 720))
        scene.configure(avatars: avatars, population: 3, localCount: 3)
        let view = FriendNotesView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        defer { view.stop() }
        let posts = avatars.enumerated().map { PlazaSpeechPost(id: "post-\($0.offset)", speaker: $0.element,
            name: $0.element.name, text: "Hello", destination: .journal(nil)) }
        view.configure(scene: scene, friends: [], paused: false, largerText: false, islands: [], reserved: [],
            showPosts: false, journalPosts: posts, maxPosts: 3, onSelect: { _ in })
        scene.acceptFFLAnchors([[0,0.2,0.65]])
        XCTAssertEqual(view.visibleCardCount, 1)
        scene.acceptFFLAnchors([[0,0.2,0.65],[1,0.5,0.65],[2,0.8,0.65]])
        XCTAssertEqual(view.visibleCardCount, 3)
    }

    func testJournalUsesItsAuthorAndTracksRendererHeadPositions() throws {
        let author = Avatar(name: "Author"), other = Avatar(name: "Other")
        let scene = PlazaScene(size: CGSize(width: 1280, height: 720))
        scene.configure(avatars: [other, author], population: 2, localCount: 2)
        let view = FriendNotesView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        defer { view.stop() }
        let post = PlazaSpeechPost(id: "journal-test", speaker: author, name: author.name, text: "Hello from this Mii", destination: .journal(nil))
        view.configure(scene: scene, friends: [], paused: false, largerText: false, islands: [], reserved: [],
                       showPosts: false, journalPost: post, onSelect: { _ in })
        XCTAssertEqual(scene.noteIndices, [1])
        scene.acceptFFLAnchors([[1, 0.5, 0.7]])
        let first = try XCTUnwrap(view.visiblePosts.first)
        XCTAssertEqual(first.speakerID, author.id)
        XCTAssertEqual(first.pointerX, first.head.x, accuracy: 0.01)
        XCTAssertLessThan(first.frame.maxY, first.head.y)
        scene.acceptFFLAnchors([[1, 0.55, 0.75]])
        let moved = try XCTUnwrap(view.visiblePosts.first)
        XCTAssertEqual(moved.frame.minX - first.frame.minX, 64, accuracy: 0.01)
        XCTAssertEqual(moved.frame.minY - first.frame.minY, 36, accuracy: 0.01)
        XCTAssertEqual(moved.pointerX, moved.head.x, accuracy: 0.01)
        scene.acceptFFLAnchors([[0, 0.4, 0.5]])
        XCTAssertEqual(view.visibleCardCount, 0, "A different Mii's anchor cannot be used for this author")
        scene.acceptFFLAnchors([[1, 0.55, 0.75]])
        XCTAssertEqual(view.visibleCardCount, 1)
        scene.resize(CGSize(width: 640, height: 480))
        view.setFrameSize(CGSize(width: 640, height: 480))
        scene.acceptFFLAnchors([[1, 0.55, 0.75]])
        let resized = try XCTUnwrap(view.visiblePosts.first)
        XCTAssertEqual(resized.head.x, 352, accuracy: 0.01)
        XCTAssertEqual(resized.head.y, 360, accuracy: 0.01)
        XCTAssertEqual(resized.pointerX, resized.head.x, accuracy: 0.01)
    }

    func testFriendSpeakerStaysTheSameWhenTheirOverheadSpaceBecomesBlocked() throws {
        let first = SharedMii(id: "one", displayName: "One", avatar: Avatar(name: "One"), note: "One speaks", presence: .online, plazaOnline: true)
        let second = SharedMii(id: "two", displayName: "Two", avatar: Avatar(name: "Two"), note: "Two speaks", presence: .online, plazaOnline: true)
        let scene = PlazaScene(size: CGSize(width: 1280, height: 720))
        scene.configure(avatars: [first.avatar, second.avatar], population: 2)
        let view = FriendNotesView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        defer { view.stop() }
        view.configure(scene: scene, friends: [first, second], paused: false, largerText: false,
                       islands: [], reserved: [], onSelect: { _ in })
        scene.acceptFFLAnchors([[0, 0.4, 0.7], [1, 0.6, 0.7]])
        let initial = try XCTUnwrap(view.visiblePosts.first)
        XCTAssertEqual(initial.speakerID, second.avatar.id)
        scene.acceptFFLAnchors([[0, 0.4, 0.7], [1, 0.6, 0.05]])
        XCTAssertEqual(view.visibleCardCount, 0, "Do not switch to a different speaker when this Mii reaches the top edge")
        scene.acceptFFLAnchors([[0, 0.4, 0.7], [1, 0.65, 0.7]])
        XCTAssertEqual(view.visiblePosts.first?.speakerID, initial.speakerID)
        view.configure(scene: scene, friends: [], paused: false, largerText: false,
                       islands: [], reserved: [], showPosts: false, onSelect: { _ in })
        XCTAssertTrue(scene.noteIndices.isEmpty)
        XCTAssertEqual(view.visibleCardCount, 0)
    }

    func testJournalSelectionPreservesAuthorIdentityIncludingDeletedAuthors() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let author = Avatar(name: "Different author")
        model.document.avatars.append(author)
        var note = LocalNote(authorID: author.id, author: author.name, appID: nil, text: "My own post")
        note.shared = false
        model.document.notes = [note]
        model.bubbleSelections[0] = 0
        XCTAssertEqual(model.journalPost().speaker.id, author.id)
        model.document.avatars.removeAll { $0.id == author.id }
        XCTAssertEqual(model.journalPost().speaker.id, author.id)
        XCTAssertNotEqual(model.journalPost().speaker.id, model.document.primaryAvatar.id)
        model.bubbleSelections[0] = 1
        XCTAssertEqual(model.journalPost().speaker.id, model.document.primaryAvatar.id)
        await model.flush()
        try await model.storage.endSession()
    }

    func testBatchKeepsAuthoredNotesWithTheirSpeakersAndUsesDistinctGuides() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.scene.setMoving(false); model.audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let secondary = Avatar(name: "Local author"), guide = Avatar(name: "Guide")
        var privateNote = LocalNote(authorID: secondary.id, author: secondary.name, appID: nil, text: "Private authored post")
        privateNote.shared = false
        let publicNote = LocalNote(authorID: secondary.id, author: secondary.name, appID: nil, text: "Public primary post")
        XCTAssertTrue(model.mutate { $0.avatars += [secondary,guide]; $0.notes = [privateNote,publicNote] })
        let original = model.document
        let posts = model.journalPosts()
        XCTAssertGreaterThanOrEqual(posts.count, 3)
        XCTAssertLessThanOrEqual(posts.count, 6)
        XCTAssertEqual(Set(posts.map { $0.speaker.id }).count, posts.count)
        XCTAssertEqual(posts.first { $0.id == privateNote.id.uuidString }?.speaker.id, secondary.id)
        XCTAssertEqual(posts.first { $0.id == publicNote.id.uuidString }?.speaker.id, model.document.primaryAvatar.id)
        XCTAssertEqual(model.document, original)
        await model.flush(); try await model.storage.endSession()
    }

    func testNativeJournalSpeechFollowsWalkingAuthor() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_SPEECH_QA"] == "1" else { throw XCTSkip("Opt-in live speech tracking fixture") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.scene.setMoving(false); model.audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        let author = model.document.primaryAvatar
        model.document.notes = [LocalNote(authorID: author.id, author: author.name, appID: nil,
                                         text: "A little walk around the plaza.")]
        model.document.preferences.ambientSound = false
        model.scene.finishEntrance()
        model.advanceBubblePresentation(by: 12)
        model.document.preferences.pausePosts = true
        let host = NSHostingView(rootView: PlazaView(model: model))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func noteLayer(_ view: NSView) -> FriendNotesView? {
            if let view = view as? FriendNotesView { return view }
            return view.subviews.compactMap(noteLayer).first
        }
        var layer: FriendNotesView?
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
            layer = noteLayer(host)
            if layer?.visibleCardCount ?? 0 > 0 { break }
        }
        let notes = try XCTUnwrap(layer)
        let first = try XCTUnwrap(notes.visiblePosts.first)
        // The planner may show a guide when the author's overhead space is
        // blocked. Verify the displayed post's own speaker, then follow that
        // same identity throughout the live interval.
        let expectedSpeaker = try XCTUnwrap(model.journalPosts().first { $0.id == first.id }).speaker.id
        XCTAssertEqual(first.speakerID, expectedSpeaker)
        XCTAssertLessThan(first.frame.maxY, first.head.y)
        XCTAssertEqual(first.pointerX, first.head.x, accuracy: 0.01)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture(_ name: String) throws {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
        }
        try capture("speech-following-before.png")
        var followed = false
        // Visitors may finish a full idle animation before starting to walk.
        for _ in 0..<600 {
            try await Task.sleep(for: .milliseconds(100))
            guard let next = notes.visiblePosts.first(where: { $0.id == first.id }) else { continue }
            XCTAssertEqual(next.speakerID, first.speakerID)
            XCTAssertLessThan(next.frame.maxY, next.head.y)
            XCTAssertEqual(next.pointerX, next.head.x, accuracy: 0.01)
            if hypot(next.head.x - first.head.x, next.head.y - first.head.y) > 4 &&
                hypot(next.frame.midX - first.frame.midX, next.frame.midY - first.frame.midY) > 4 { followed = true; break }
        }
        XCTAssertTrue(followed, "The live renderer must move the speech box with its walking author")
        try capture("speech-following-after.png")
        await model.flush()
        try await model.storage.endSession()
    }
}
