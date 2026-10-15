import XCTest
import SwiftUI
import AppKit
import PlazaCore
@testable import MacPlaza

final class BirthdayCelebrationTests: XCTestCase {
    @MainActor func testSecondaryBirthdayCannotTriggerPrimaryCelebration() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a display") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.birthdayCelebration.dismiss(); model.audio.update(enabled: false); model.scene.setMoving(false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let now = Date(), parts = Calendar.current.dateComponents([.month, .day], from: now)
        var secondary = Avatar(name: "Guest birthday")
        secondary.features.birthMonth = parts.month!; secondary.features.birthDay = parts.day!
        model.document.avatars.append(secondary)
        let window = NSWindow(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.isReleasedWhenClosed = false; model.window = window
        defer { window.close() }
        model.checkBirthday(now: now)
        XCTAssertNil(model.birthdayReceipt.year)
        XCTAssertNil(model.birthdayCelebration.panel)
        let primaryID = model.document.primaryAvatar.id
        let index = try XCTUnwrap(model.document.avatars.firstIndex { $0.id == primaryID })
        model.document.avatars[index].features.birthMonth = parts.month!
        model.document.avatars[index].features.birthDay = parts.day!
        model.checkBirthday(now: now)
        XCTAssertEqual(model.birthdayReceipt.year, Calendar.current.component(.year, from: now))
        XCTAssertNotNil(model.birthdayCelebration.panel)
        model.birthdayCelebration.dismiss()
        model.checkBirthday(now: now)
        XCTAssertNil(model.birthdayCelebration.panel, "Reopening Plaza must not repeat the effect")
        await model.flush(); try await model.storage.endSession()
    }
    func testBirthdayUsesLocalCalendarAndPersistsOnlyOneCelebrationPerYear() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = ISO8601DateFormatter().date(from: "2026-10-16T02:00:00Z")!
        var avatar = Avatar(); avatar.features.birthMonth = 10; avatar.features.birthDay = 15
        let file = root.appendingPathComponent("birthday.json")
        let receipt = BirthdayCelebrationReceipt(url: file)
        XCTAssertTrue(receipt.claim(avatar: avatar, now: date, calendar: calendar))
        XCTAssertFalse(receipt.claim(avatar: avatar, now: date, calendar: calendar))
        XCTAssertFalse(BirthdayCelebrationReceipt(url: file).claim(avatar: avatar, now: date, calendar: calendar))
        let nextYear = calendar.date(byAdding: .year, value: 1, to: date)!
        XCTAssertTrue(receipt.claim(avatar: avatar, now: nextYear, calendar: calendar))
        XCTAssertEqual(String(data: try Data(contentsOf: file), encoding: .utf8), "2027")
    }
    func testUnsetInvalidAndLeapDayBirthdaysDoNotBecomeDifferentDates() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let receipt = BirthdayCelebrationReceipt(url: root.appendingPathComponent("birthday.json"))
        let formatter = ISO8601DateFormatter()
        let march = formatter.date(from: "2026-03-01T12:00:00Z")!
        var avatar = Avatar()
        XCTAssertFalse(receipt.claim(avatar: avatar, now: march, calendar: calendar))
        avatar.features.birthMonth = 2; avatar.features.birthDay = 31
        XCTAssertFalse(receipt.claim(avatar: avatar, now: march, calendar: calendar))
        avatar.features.birthDay = 29
        XCTAssertFalse(receipt.claim(avatar: avatar, now: march, calendar: calendar))
        XCTAssertTrue(receipt.claim(avatar: avatar, now: formatter.date(from: "2028-02-29T12:00:00Z")!, calendar: calendar))
    }
    @MainActor func testOverlayNeverTakesFocusOrMouseAndCleansUp() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a display") }
        _ = NSApplication.shared
        let key = NSApp.keyWindow
        let controller = BirthdayCelebrationController()
        controller.show(name: "Birthday QA", screen: screen, reducedMotion: true)
        XCTAssertTrue(controller.panel?.ignoresMouseEvents == true)
        XCTAssertTrue(controller.panel?.styleMask.contains(.nonactivatingPanel) == true)
        XCTAssertTrue(NSApp.keyWindow === key)
        try await Task.sleep(for: .milliseconds(3250))
        XCTAssertNil(controller.panel)
    }
}
