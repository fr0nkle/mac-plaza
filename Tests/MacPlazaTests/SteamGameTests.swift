import XCTest
import AppKit
import PlazaCore
@testable import MacPlaza

final class SteamGameTests: XCTestCase {
    private func fixture(_ root: URL, id: UInt32 = 2379780, name: String = "Balatro", directory: String = "Balatro", flags: String = "4") throws -> URL {
        let apps = root.appendingPathComponent("steamapps")
        let application = apps.appendingPathComponent("common/\(directory)/\(directory).app")
        let contents = application.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleIdentifier": "test.game.\(id)", "CFBundleExecutable": "game", "CFBundleName": directory, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data().write(to: contents.appendingPathComponent("MacOS/game"))
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let manifest = "\"AppState\" { \"appid\" \"\(id)\" \"name\" \"\(escapedName)\" \"installdir\" \"\(directory)\" \"StateFlags\" \"\(flags)\" }"
        try Data(manifest.utf8).write(to: apps.appendingPathComponent("appmanifest_\(id).acf"))
        return application
    }

    func testDiscoversLibrariesAndLaunchesByGameIDRatherThanGameExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("Steam"), extra = root.appendingPathComponent("External Steam Library")
        let balatro = try fixture(base)
        let second = try fixture(extra, id: 123, name: "A \"Quoted\" Game", directory: "Other Game")
        let libraries = "// additional drive\n\"libraryfolders\" { \"0\" { \"path\" \"\(base.path)\" } \"1\" { \"path\" \"\(extra.path)\" } }"
        try Data(libraries.utf8).write(to: base.appendingPathComponent("steamapps/libraryfolders.vdf"))
        let games = SteamGames.installed(root: base)
        XCTAssertEqual(games.map(\.id), [123, 2379780])
        XCTAssertEqual(games[0].name, "A \"Quoted\" Game")
        XCTAssertEqual(games[0].applicationURL.resolvingSymlinksInPath().path, second.resolvingSymlinksInPath().path)
        XCTAssertEqual(games[1].applicationURL.resolvingSymlinksInPath().path, balatro.resolvingSymlinksInPath().path)
        XCTAssertEqual(games[1].launchURL.absoluteString, "steam://rungameid/2379780")
        XCTAssertEqual(SteamGames.game(forApplication: balatro), games[1])
        XCTAssertNil(SteamGames.game(forApplication: URL(fileURLWithPath: "/Applications/Calculator.app")))
    }

    func testIncompleteMissingWindowsOnlyAndInvalidManifestTargetsAreExcluded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = try fixture(root)
        _ = try fixture(root, id: 2, name: "Downloading", directory: "Downloading", flags: "2")
        let windows = try fixture(root, id: 3, name: "Windows", directory: "Windows")
        try FileManager.default.removeItem(at: windows)
        let broken = try fixture(root, id: 4, name: "Broken", directory: "Broken")
        try FileManager.default.removeItem(at: broken.appendingPathComponent("Contents/MacOS/game"))
        let apps = root.appendingPathComponent("steamapps")
        for (filename, body) in [
            ("5", "\"appid\" \"5\" \"installdir\" \"../Balatro\""),
            ("6", "\"appid\" \"2379780\" \"installdir\" \"Balatro\""),
            ("7", "\"appid\" \"0\" \"installdir\" \"Balatro\"")
        ] {
            try Data("\"AppState\" { \"name\" \"Bad\" \"StateFlags\" \"4\" \(body) }".utf8).write(to: apps.appendingPathComponent("appmanifest_\(filename).acf"))
        }
        XCTAssertEqual(SteamGames.installed(root: root).map(\.id), [2379780])
        try FileManager.default.removeItem(at: application)
        XCTAssertTrue(SteamGames.installed(root: root).isEmpty)
    }

    @MainActor func testAddSaveReloadDuplicateReplaceAndUndoPreserveGameIdentity() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = try fixture(root.appendingPathComponent("Steam"))
        let model = PlazaModel(directory: root.appendingPathComponent("Plaza"))
        defer { model.audio.update(enabled: false, allowPreview: false) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.document.preferences.ambientSound = false
        model.mutate { $0.apps = [] }
        model.addApps([application])
        XCTAssertNil(model.error)
        let game = try XCTUnwrap(model.document.apps.first)
        XCTAssertEqual(game.steamAppID, 2379780)
        XCTAssertEqual(game.label, "Balatro")
        XCTAssertEqual(model.resolvedURL(game)?.resolvingSymlinksInPath().path, application.resolvingSymlinksInPath().path)
        let info = AppPreviewInfo(app: game, url: application)
        XCTAssertEqual(info.category, "Steam game")
        XCTAssertNil(info.version, "The LÖVE engine version must not be presented as Balatro's version")
        model.addApps([application])
        XCTAssertEqual(model.document.apps.count, 1)
        await model.flush()
        let saved = try await model.storage.load()
        XCTAssertEqual(saved?.apps, [game])
        var old = AppIsland(label: "My shortcut", bundleID: "test.old")
        old.customIcon = Data([1, 2, 3])
        model.mutate { $0.apps = [old] }
        model.addApps([application], replacing: old)
        XCTAssertEqual(model.document.apps[0].id, old.id)
        XCTAssertEqual(model.document.apps[0].label, old.label)
        XCTAssertEqual(model.document.apps[0].customIcon, old.customIcon)
        XCTAssertEqual(model.document.apps[0].steamAppID, 2379780)
        model.undoLayout()
        XCTAssertEqual(model.document.apps, [old])
        var mismatched = game; mismatched.steamAppID = 123
        model.launch(mismatched)
        XCTAssertTrue(model.error?.contains("moved or changed") == true)
        XCTAssertTrue(model.launching.isEmpty)
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor func testInstalledBalatroCanBeAddedWithItsOwnIconWithoutLaunchingIt() throws {
        let url = SteamGames.defaultRoot.appendingPathComponent("steamapps/common/Balatro/Balatro.app")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Balatro is not installed") }
        let game = try XCTUnwrap(SteamGames.installed().first { $0.id == 2379780 })
        let island = try PlazaModel.island(at: game.applicationURL)
        XCTAssertEqual(island.label, "Balatro")
        XCTAssertEqual(island.steamAppID, 2379780)
        XCTAssertEqual(island.bundleID, "com.Balatro.localthunk")
        XCTAssertEqual(game.launchURL.absoluteString, "steam://rungameid/2379780")
        XCTAssertNotNil(NSWorkspace.shared.icon(forFile: game.applicationURL.path).tiffRepresentation)
    }
}
