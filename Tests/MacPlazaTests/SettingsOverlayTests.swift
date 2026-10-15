import XCTest
import AppKit
import SwiftUI
@testable import MacPlaza

final class SettingsOverlayTests: XCTestCase {
    @MainActor func testSettingsCategoryVisualFixture() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_SETTINGS_QA"] == "1" else { throw XCTSkip("Opt-in Settings category captures") }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/settings-categories")
        let model = PlazaModel(directory: root.appendingPathComponent("plaza"))
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        model.document.preferences.ambientSound = false
        defer { model.audio.update(enabled: false, allowPreview: false) }
        let original = model.document
        for (category, width, height) in [(nil as SettingsCategory?, 760, 820), (nil, 640, 507), (.sound, 760, 820), (.display, 760, 820), (.system, 760, 820)] {
            let host = NSHostingView(rootView: PreferencesView(model: model, fillsOverlay: true, initialCategory: category).frame(width: CGFloat(width), height: CGFloat(height)))
            let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try png.write(to: root.appendingPathComponent("\(category?.rawValue ?? "categories")-\(width)x\(height).png"))
            window.orderOut(nil)
        }
        XCTAssertEqual(model.document, original, "Browsing Settings must not change preferences")
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor func testSettingsOverlayRetainsPlazaAndCleansUpMusicPreviewOnClose() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "MacPlaza.SettingsOverlay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = PlazaModel(directory: directory)
        let controller = DesktopPlazaController(model: model, defaults: defaults)
        model.desktop = controller
        let main = NSWindow(contentRect: NSRect(x: 90, y: 100, width: 1060, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        model.window = main
        defer {
            model.audio.update(enabled: false, allowPreview: false)
            controller.disable(showWindow: false); controller.shutdown(); main.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.document.preferences.musicVolume = 0
        model.document.preferences.settingsMusicVolume = 0
        model.document.preferences.ambientSound = true
        controller.enable(activate: false)
        let wallpaper = try XCTUnwrap(controller.window)
        let renderer = try XCTUnwrap(wallpaper.contentView)
        model.sheet = .preferences
        let settings = try XCTUnwrap(controller.menuWindow)
        XCTAssertEqual(settings.title, "Settings")
        XCTAssertEqual(settings.identifier?.rawValue, "MacPlazaDesktopSettings")
        XCTAssertTrue(settings.isVisible)
        XCTAssertTrue(settings.styleMask.contains(.resizable))
        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(wallpaper.contentView === renderer)
        XCTAssertTrue(wallpaper.ignoresMouseEvents)
        model.desktopVisible = true; model.desktopMenuVisible = true; model.windowVisible = false
        XCTAssertTrue(model.audioEligible)
        XCTAssertEqual(model.musicTrack, .settings)
        XCTAssertEqual(model.isMoving, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        try await Task.sleep(for: .milliseconds(100))
        let preview = directory.appendingPathComponent("Preview.wav")
        try PlazaAudio.loop().write(to: preview)
        try model.audio.preview(preview, track: .plaza, volume: 0)
        XCTAssertNotNil(model.audio.previewTrack)
        XCTAssertFalse(controller.windowShouldClose(settings))
        for _ in 0..<50 where model.audio.previewTrack != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(model.audio.previewTrack, "Closing the overlay must stop the Settings audition")
        XCTAssertNil(model.sheet)
        XCTAssertNil(controller.menuWindow)
        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(model.desktopInteractive)
        XCTAssertTrue(wallpaper.contentView === renderer)
        model.sheet = .preferences
        controller.disable()
        XCTAssertNil(controller.menuWindow)
        XCTAssertNil(controller.window)
        XCTAssertFalse(model.wallpaperEnabled)
        XCTAssertTrue(main.isVisible, "Disabling wallpaper still restores the ordinary app window")
        XCTAssertEqual(model.sheet?.id, "preferences")
        await model.flush()
        try await model.storage.endSession()
    }
}
