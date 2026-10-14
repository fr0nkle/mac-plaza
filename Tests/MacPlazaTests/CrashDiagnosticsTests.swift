import XCTest
import AppKit
@testable import MacPlaza

final class CrashDiagnosticsTests: XCTestCase {
    @MainActor private func loadedModel(at directory: URL) async throws -> PlazaModel {
        _ = NSApplication.shared
        let model = PlazaModel(directory: directory)
        for _ in 0..<300 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        return model
    }

    @MainActor func testCleanFirstLaunchAndCleanRelaunchDoNotOfferDiagnostics() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await loadedModel(at: root)
        XCTAssertFalse(first.previousSessionInterrupted)
        XCTAssertFalse(first.diagnosticsRecoveryOfferPending)
        await first.flush(); try await first.storage.endSession()
        let second = try await loadedModel(at: root)
        XCTAssertFalse(second.previousSessionInterrupted)
        XCTAssertFalse(second.diagnosticsRecoveryOfferPending)
        await second.flush(); try await second.storage.endSession()
    }

    @MainActor func testInterruptedLaunchQueuesOfferAndKeepsSafeModeWithoutAWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("running".utf8).write(to: root.appendingPathComponent("plaza.json.session"))
        let model = try await loadedModel(at: root)
        XCTAssertTrue(model.previousSessionInterrupted)
        XCTAssertTrue(model.document.preferences.safeMode)
        XCTAssertTrue(model.diagnosticsRecoveryOfferPending)
        model.offerDiagnosticsAfterInterruptedSession()
        await Task.yield()
        XCTAssertNil(model.diagnosticsRecoveryAlert, "Wait for an actual app window")
        XCTAssertTrue(model.diagnosticsRecoveryOfferPending, "Do not lose the offer before the window attaches")
        await model.flush(); try await model.storage.endSession()
        let next = try await loadedModel(at: root)
        XCTAssertTrue(next.document.preferences.safeMode, "Safe mode alone must not be mistaken for another crash")
        XCTAssertFalse(next.previousSessionInterrupted)
        XCTAssertFalse(next.diagnosticsRecoveryOfferPending)
        await next.flush(); try await next.storage.endSession()
    }

    @MainActor func testCorruptSavedDataPreservesRecoveryErrorAndPendingDiagnostics() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("plaza.json")
        try Data("broken saved plaza".utf8).write(to: file)
        try Data("running".utf8).write(to: root.appendingPathComponent("plaza.json.session"))
        let model = try await loadedModel(at: root)
        XCTAssertTrue(model.recoveryRequired)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.previousSessionInterrupted)
        XCTAssertTrue(model.diagnosticsRecoveryOfferPending)
        model.offerDiagnosticsAfterInterruptedSession(); await Task.yield()
        XCTAssertNil(model.diagnosticsRecoveryAlert, "Do not replace the saved-data recovery alert")
        XCTAssertEqual(try Data(contentsOf: file), Data("broken saved plaza".utf8))
        try await model.storage.endSession()
    }
}
