import XCTest
import AppKit
import PlazaCore
@testable import MacPlaza

final class RotatingHomeTests: XCTestCase {
    private func fakeApp(_ name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name + ".app")
        let contents = url.appendingPathComponent("Contents"), executable = contents.appendingPathComponent("MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture, never execute".utf8).write(to: executable)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.rotation.\(name)",
            "CFBundleName": name, "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    @MainActor func testRotationPreservesPinsDefersWhileBusyAndSkipsRemovedApps() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.rotationScanTask?.cancel(); model.audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        let first = try PlazaModel.island(at: fakeApp("Pinned", in: root))
        let recent = try PlazaModel.island(at: fakeApp("Recent", in: root))
        let game = try PlazaModel.island(at: fakeApp("Game", in: root))
        model.mutate { $0.apps = [first] }
        XCTAssertTrue(model.rotatingHomeEnabled, "Rotation is the default for a new plaza")
        model.mutate { $0.preferences.rotatingHomeScreen = false }
        // Supply a controlled local catalog without scanning the user's applications.
        model.document.preferences.rotatingHomeScreen = true
        model.installedRotationApps = [first, recent, game]
        model.recordRecentLaunch(recent)
        model.rotationNeedsRefresh = true
        model.previewAppID = first.id
        model.applyPendingHomeRotation()
        XCTAssertFalse(model.rotationReady)
        XCTAssertTrue(model.rotationNeedsRefresh)
        model.previewAppID = nil
        model.applyPendingHomeRotation()
        XCTAssertEqual(Set(model.homeApps.map(\.id)), Set([first.id, recent.id]))
        XCTAssertEqual(model.document.apps, [first])
        let snapshot = model.homeApps
        model.recordRecentLaunch(game)
        XCTAssertEqual(model.homeApps, snapshot, "New launches feed the next mix without moving current icons")
        model.beginChangingApps()
        XCTAssertEqual(model.homeApps, [first], "Change Apps edits saved pins")
        model.editing = false
        model.pinHomeApp(recent)
        XCTAssertEqual(model.document.apps, [first, recent])
        model.mutate { $0.preferences.rotatingHomeScreen = false }
        XCTAssertEqual(model.homeApps, [first, recent])
        XCTAssertEqual(model.document.apps, [first, recent])
        model.document.preferences.rotatingHomeScreen = true
        try FileManager.default.removeItem(at: URL(fileURLWithPath: recent.path!))
        model.rotationNeedsRefresh = true
        model.applyPendingHomeRotation()
        XCTAssertFalse(model.homeApps.contains { $0.id == recent.id })
        try FileManager.default.removeItem(at: URL(fileURLWithPath: first.path!))
        try FileManager.default.removeItem(at: URL(fileURLWithPath: game.path!))
        model.rotationNeedsRefresh = true
        model.applyPendingHomeRotation()
        XCTAssertTrue(model.homeApps.isEmpty, "An empty installed catalog must not restore broken pins")
        await model.flush(); try await model.storage.endSession()
    }

    func testLocalHistoryPersistsDeduplicatesAndStableIDsSurviveRelaunches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("recent-apps.json")
        let history = RecentAppHistory(url: url), now = Date()
        var app = AppIsland(label: "Fixture", bundleID: "test.fixture", path: "/Applications/Fixture.app")
        try history.record(app, at: now)
        app.id = UUID()
        try history.record(app, at: now.addingTimeInterval(1))
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].app.id, RecentAppHistory.stableID(for: app))
        var older = app; older.bundleID = "test.older"
        try history.record(older, at: now.addingTimeInterval(-10))
        XCTAssertEqual(history.entries.first?.app.bundleID, app.bundleID, "Seeding running apps must preserve launch-date order")
        try history.remember([app])
        let reloaded = RecentAppHistory(url: url, now: now.addingTimeInterval(2))
        XCTAssertEqual(reloaded.entries.first?.app.id, history.entries.first?.app.id)
        XCTAssertEqual(reloaded.previous, [HomeScreenRotation.key(app)])
        XCTAssertTrue(RecentAppHistory(url: url, now: now.addingTimeInterval(91 * 86400)).entries.isEmpty)
        try Data("broken history".utf8).write(to: url)
        XCTAssertTrue(RecentAppHistory(url: url).entries.isEmpty)
    }

    func testDiscoveryStopsAtAppPackagesAndLegacyPreferencesUseTheDefault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try fakeApp("Main", in: root)
        _ = try fakeApp("HiddenHelper", in: app.appendingPathComponent("Contents"))
        XCTAssertEqual(InstalledHomeApps.applicationURLs(roots: [root]).map { $0.resolvingSymlinksInPath().path },
                       [app.resolvingSymlinksInPath().path])
        let legacy = try JSONDecoder().decode(PlazaCore.Preferences.self,
            from: Data("{\"population\":160,\"pauseMotion\":false,\"pausePosts\":false,\"privatePresentation\":false,\"safeMode\":false}".utf8))
        XCTAssertNil(legacy.rotatingHomeScreen)
    }
}
