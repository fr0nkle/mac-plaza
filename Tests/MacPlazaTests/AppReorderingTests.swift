import XCTest
import AppKit
import PlazaCore
@testable import MacPlaza

final class AppReorderingTests: XCTestCase {
    @MainActor
    func testDropsMoveToTheDestinationSlotInBothDirectionsAndPersist() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        let apps = (0..<14).map { AppIsland(label: "App \($0)", bundleID: "test.app\($0)") }
        model.mutate { $0.apps = apps }
        let original = model.document
        let characters = model.scene.fflCharacters.map(\.id)
        model.editing = true
        XCTAssertTrue(model.acceptAppDrop([apps[0].id.uuidString], onto: apps[11].id))
        XCTAssertEqual(model.document.apps, Array(apps[1...11]) + [apps[0]] + Array(apps[12...]))
        XCTAssertEqual(model.scene.fflCharacters.map(\.id), characters)
        XCTAssertEqual(model.document.avatars, original.avatars)
        XCTAssertEqual(model.document.notes, original.notes)
        model.undoLayout()
        XCTAssertEqual(model.document, original)

        XCTAssertTrue(model.acceptAppDrop([apps[11].id.uuidString], onto: apps[0].id))
        let backward = [apps[11]] + Array(apps[0..<11]) + Array(apps[12...])
        XCTAssertEqual(model.document.apps, backward)
        await model.flush()
        let saved = try await model.storage.load()
        XCTAssertEqual(saved?.apps, backward)
        XCTAssertEqual(saved?.avatars, original.avatars)
        model.undoLayout()
        XCTAssertEqual(model.document, original)
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor
    func testRejectedDropsDoNotChangeTheLayoutOrConsumeUndo() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        let apps = (0..<3).map { AppIsland(label: "App \($0)", bundleID: "test.app\($0)") }
        model.mutate { $0.apps = apps }
        let original = model.document
        XCTAssertFalse(model.acceptAppDrop([apps[0].id.uuidString], onto: apps[2].id), "Home mode cannot rearrange apps")
        model.editing = true
        XCTAssertTrue(model.acceptAppDrop([apps[0].id.uuidString], onto: apps[2].id))
        let reordered = model.document
        for items in [[], ["unrelated text"], [UUID().uuidString], [apps[0].id.uuidString], apps.prefix(2).map { $0.id.uuidString }] {
            XCTAssertFalse(model.acceptAppDrop(items, onto: apps[0].id))
            XCTAssertEqual(model.document, reordered)
        }
        XCTAssertFalse(model.acceptAppDrop([apps[0].id.uuidString], onto: UUID()))
        model.recoveryRequired = true
        XCTAssertFalse(model.acceptAppDrop([apps[0].id.uuidString], onto: apps[1].id))
        model.recoveryRequired = false
        model.undoLayout()
        XCTAssertEqual(model.document, original, "Rejected drops must not add an undo entry")
        await model.flush()
        try await model.storage.endSession()
    }
}
