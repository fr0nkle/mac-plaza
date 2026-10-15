import XCTest
import SwiftUI
import AppKit
@testable import MacPlaza

final class UpdateBadgeTests: XCTestCase {
    private let source = URL(string: "https://plaza.example.test")!
    func testOnlyConfirmedNewerDownloadCreatesBadge() {
        var state = PlazaUpdateAvailability()
        XCTAssertFalse(state.available, "Initial and offline state cannot invent an update")
        let download = source.appendingPathComponent("updates/MacPlaza.zip")
        for version in ["36", "37"] {
            state.found(version: version, displayVersion: "0.22.1", installedVersion: "37", downloadURL: download, source: source)
            XCTAssertFalse(state.available)
        }
        state.found(version: "38", displayVersion: "0.23.0", installedVersion: "37", downloadURL: download, source: source)
        XCTAssertTrue(state.available); XCTAssertEqual(state.displayVersion, "0.23.0")
        state.clear() // Both Sparkle's no-update and aborted/error callbacks clear this state.
        XCTAssertFalse(state.available); XCTAssertNil(state.version); XCTAssertNil(state.displayVersion)
        state.found(version: "1.10", displayVersion: "", installedVersion: "1.9", downloadURL: download, source: source)
        XCTAssertTrue(state.available, "Use Sparkle's numeric version comparison")
    }
    func testInformationOnlyMissingSourceAndForeignDownloadsNeverShowBadge() {
        var state = PlazaUpdateAvailability()
        for download in [nil, URL(string: "https://elsewhere.example/updates/app.zip"), URL(string: "https://plaza.example.test/other/app.zip"), source.appendingPathComponent("updates/appcast.xml")] {
            state.found(version: "38", displayVersion: "0.23", installedVersion: "37", downloadURL: download, source: source)
            XCTAssertFalse(state.available)
        }
        state.found(version: "38", displayVersion: "0.23", installedVersion: "37", downloadURL: source.appendingPathComponent("updates/app.zip"), source: nil)
        XCTAssertFalse(state.available)
    }
    @MainActor func testSettingsAndSystemUpdateBadgeLocationsRenderOnlyWhenAvailable() throws {
        _ = NSApplication.shared
        func render(_ available: Bool) throws -> NSBitmapImageRep {
            let host = NSHostingView(rootView: HStack(spacing: 24) {
                VStack(spacing: 8) { Image(systemName: "gearshape").font(.system(size: 30)); Text("Settings") }
                    .frame(width: 100, height: 100).background(.white, in: RoundedRectangle(cornerRadius: 15))
                    .modifier(PlazaUpdateIndicator(available: available, label: "Settings"))
                SettingsCategoryTile(category: .updates, height: 100, select: {}, updateAvailable: available).frame(width: 180)
            }.padding(20).background(PlazaStyle.paper).environment(\.colorScheme, .light))
            host.frame = CGRect(x: 0, y: 0, width: 344, height: 140); host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap
        }
        let available = try render(true), current = try render(false)
        func redCount(_ bitmap: NSBitmapImageRep, left: Bool) -> Int {
            var count = 0
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide where (x < bitmap.pixelsWide / 2) == left {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if c.redComponent > 0.75 && c.greenComponent < 0.35 && c.blueComponent < 0.4 { count += 1 }
            } }
            return count
        }
        for left in [true, false] {
            XCTAssertGreaterThan(redCount(available, left: left), 30, "Both Settings and System Update need a visible badge")
            XCTAssertEqual(redCount(current, left: left), 0, "Current/error state has no badge")
        }
        if ProcessInfo.processInfo.environment["PLAZA_MIIVERSE_QA"] == "1" {
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/miiverse-redesign")
            try XCTUnwrap(available.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("update-badges.png"))
            try XCTUnwrap(current.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("update-current.png"))
        }
    }
}
