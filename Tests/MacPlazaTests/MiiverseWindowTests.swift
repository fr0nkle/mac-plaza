import XCTest
import AppKit
import SwiftUI
import PlazaCore
@testable import MacPlaza

@MainActor final class MiiverseWindowTests: XCTestCase {
    func testIndependentResizableWindowKeepsPlazaAndRestoresSizeWithFeedDefault() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        let frameName = "MiiverseWindowTests-" + UUID().uuidString
        let controller = MiiverseWindowController(model: model, frameAutosaveName: frameName)
        model.miiverseWindow = controller
        let plaza = NSWindow(contentRect: NSRect(x: 70, y: 90, width: 1200, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        plaza.isReleasedWhenClosed = false; plaza.title = "Plaza behind Miiverse"; model.window = plaza
        defer { controller.close(); plaza.close(); model.audio.update(enabled: false); model.scene.setMoving(false); NSWindow.removeFrame(usingName: frameName); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        model.document.preferences.ambientSound = false
        plaza.orderFront(nil)
        let original = model.document
        model.openMiiverse()
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window !== plaza); XCTAssertTrue(plaza.isVisible)
        XCTAssertTrue(window.styleMask.contains(.resizable)); XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertEqual(window.contentMinSize, MiiverseWindowController.minimumSize)
        XCTAssertEqual(window.title, "Miiverse")
        XCTAssertEqual(MiiverseView(model: model).initialPage, .feed)
        XCTAssertNil(model.selectedNoteID)
        model.windowVisible = false; model.miiverseVisible = true
        XCTAssertTrue(model.audioEligible, "The separate Miiverse window counts as visible for its music")
        model.windowVisible = true
        XCTAssertTrue(model.isMoving, "Plaza can keep moving behind Miiverse")
        let originalHost = window.contentView
        let draftSheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        draftSheet.isReleasedWhenClosed = false
        window.beginSheet(draftSheet, completionHandler: { _ in })
        model.openMiiverse()
        XCTAssertTrue(window.contentView === originalHost, "Focusing an open composer must preserve its draft UI")
        XCTAssertTrue(window.attachedSheet === draftSheet)
        window.endSheet(draftSheet); draftSheet.close()
        window.setContentSize(NSSize(width: 910, height: 610))
        window.saveFrame(usingName: frameName)
        let resized = window.frame.size
        window.close()
        XCTAssertNil(controller.window); XCTAssertNil(model.sheet)
        XCTAssertTrue(plaza.isVisible)
        model.openMiiverse()
        XCTAssertEqual(controller.window?.frame.size, resized)
        XCTAssertEqual(model.document, original)
        controller.close()
        await model.flush(); try await model.storage.endSession()
    }

    func testBirthdayEditingChangesOnlyThePrimaryProfileAndValidatesCalendarDays() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false); model.scene.setMoving(false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let original = model.document
        XCTAssertFalse(model.setPrimaryBirthday(month: 4, day: 31))
        XCTAssertFalse(model.setPrimaryBirthday(month: 13, day: 1))
        XCTAssertFalse(model.setPrimaryBirthday(month: 0, day: 8))
        XCTAssertFalse(model.setPrimaryBirthday(month: 2, day: 30))
        XCTAssertEqual(model.document, original)
        XCTAssertTrue(model.setPrimaryBirthday(month: 2, day: 29))
        var expected = original
        let index = try XCTUnwrap(expected.avatars.firstIndex { $0.id == expected.primaryAvatar.id })
        expected.avatars[index].features.birthMonth = 2; expected.avatars[index].features.birthDay = 29
        XCTAssertEqual(model.document, expected)
        await model.flush()
        let stored = try await model.storage.load()
        XCTAssertEqual(stored, expected)
        XCTAssertTrue(model.setPrimaryBirthday(month: 0, day: 0))
        expected.avatars[index].features.birthMonth = 0; expected.avatars[index].features.birthDay = 0
        XCTAssertEqual(model.document, expected)
        await model.flush(); try await model.storage.endSession()
    }

    func testResponsiveFeedCommunitiesAndBirthdayAtMinimumAndLargeSizes() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_MIIVERSE_QA"] == "1" else { throw XCTSkip("Opt-in responsive screenshots") }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.miiverseWindow.close(); model.audio.update(enabled: false); model.scene.setMoving(false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        model.document.preferences.ambientSound = false
        let author = model.document.primaryAvatar
        model.document.notes = [LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Activity Feed opens with all my posts.")]
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/miiverse-window")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (width, height) in [(720, 540), (1000, 720), (1300, 820)] {
            for page in [MiiversePage.feed, .communities, .user] {
                let host = NSHostingView(rootView: MiiverseView(model: model, initialPage: page))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                try await Task.sleep(for: .milliseconds(180)); host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("\(page.rawValue)-\(width).png"))
                window.close()
            }
        }
        await model.flush(); try await model.storage.endSession()
    }
}
