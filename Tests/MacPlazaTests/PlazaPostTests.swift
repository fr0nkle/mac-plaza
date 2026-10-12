import XCTest
import AppKit
import SwiftUI
import PlazaCore
@testable import MacPlaza

final class PlazaPostTests: XCTestCase {
    func testPostsHaveQuietGapsAndNeverAppearTogether() {
        var cadence = PlazaPostCadence()
        var journal = 0, friends = 0, quiet = 0
        for _ in 0..<104 {
            switch cadence.presentation {
            case .quiet: quiet += 1
            case .journal: journal += 1
            case .friends: friends += 1
            }
            cadence.advance(by: 1)
        }
        XCTAssertEqual(journal, 20)
        XCTAssertEqual(friends, 20)
        XCTAssertEqual(quiet, 64, "Most plaza time should have no speech panels")
        XCTAssertEqual(cadence.presentation, .quiet)
    }

    func testHoldingAPostPreservesItsReadingTimeAndInvalidElapsedIsIgnored() {
        var cadence = PlazaPostCadence()
        cadence.advance(by: 12)
        XCTAssertEqual(cadence.presentation, .journal)
        cadence.advance(by: 40, held: true)
        XCTAssertEqual(cadence.presentation, .journal)
        cadence.advance(by: .infinity); cadence.advance(by: .nan); cadence.advance(by: -10)
        XCTAssertEqual(cadence.elapsed, 12)
        cadence.advance(by: 10)
        XCTAssertEqual(cadence.presentation, .quiet)
        cadence.advance(by: 14)
        XCTAssertEqual(cadence.presentation, .friends)
        cadence.advance(by: 10)
        XCTAssertEqual(cadence.presentation, .quiet)
    }

    @MainActor func testModelFreezesPostsDuringInteractionAndCyclesEveryJournalEntry() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.scene.finishEntrance()
        model.advanceBubblePresentation(by: 12)
        XCTAssertEqual(model.postPresentation, .journal)
        XCTAssertEqual(model.bubbleSelections[0], 0)
        model.holdBubble(0, held: true)
        model.advanceBubblePresentation(by: 40)
        XCTAssertEqual(model.postPresentation, .journal)
        model.holdBubble(0, held: false)
        model.document.preferences.pausePosts = true
        model.advanceBubblePresentation(by: 40)
        XCTAssertEqual(model.postPresentation, .journal)
        model.document.preferences.pausePosts = false
        model.sheet = .feed
        model.advanceBubblePresentation(by: 40)
        XCTAssertEqual(model.postPresentation, .journal)
        model.sheet = nil
        model.advanceBubblePresentation(by: 10)
        XCTAssertEqual(model.postPresentation, .quiet)
        model.advanceBubblePresentation(by: 42)
        XCTAssertEqual(model.postPresentation, .journal)
        XCTAssertEqual(model.bubbleSelections[0], 1, "Advance by one instead of skipping every third post")
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor func testRenderPostDesignForVisualReview() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_POST_QA"] == "1" else { throw XCTSkip("Opt-in post visual review") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let avatar = model.document.primaryAvatar
        model.document.notes = [LocalNote(authorID: avatar.id, author: "Alex", appID: nil, text: "A little break before the next adventure. What are you playing today?")]
        model.document.preferences.pausePosts = true
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture<V: View>(_ view: V, size: CGSize, name: String) throws {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
        }
        try capture(BubbleView(model: model, offset: 0).frame(width: 240).padding(35).background(PlazaStyle.paper),
                    size: CGSize(width: 310, height: 180), name: "wiiu-journal-bubble.png")
        try capture(FeedView(model: model), size: CGSize(width: 660, height: 670), name: "wiiu-journal.png")
        await model.flush()
        try await model.storage.endSession()
    }
}
