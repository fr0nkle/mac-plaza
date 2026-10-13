import XCTest
import PlazaCore
@testable import MacPlaza

final class MiiLibraryTests: XCTestCase {
    @MainActor
    func testSavingHundredthMiiEditingAtCapacityAndRejectingOverflow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer { model.scene.setMoving(false); try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        XCTAssertTrue(model.mutate { doc in
            doc.preferences.safeMode = true
            doc.avatars = (0..<99).map { Avatar(name: "Mii \($0)", outfit: $0 % 12) }
            doc.primaryAvatarID = doc.avatars.first?.id
        })
        var last = Avatar(name: "Hundredth Mii", outfit: 3)
        XCTAssertTrue(model.saveMii(last))
        XCTAssertEqual(model.document.avatars.count, 100)
        last.name = "Edited at capacity"
        XCTAssertTrue(model.saveMii(last))
        XCTAssertEqual(model.document.avatars.last, last)
        let full = model.document
        XCTAssertFalse(model.saveMii(Avatar(name: "Overflow", outfit: 0)))
        XCTAssertEqual(model.document, full)
        await model.flush()
        let saved = try await model.storage.load()
        XCTAssertEqual(saved, full)
        try await model.storage.endSession()
    }
}
