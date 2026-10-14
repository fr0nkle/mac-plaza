import XCTest
@testable import MacPlaza

final class ResourceFallbackTests: XCTestCase {
    private func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testInstalledAppWithoutMusicDoesNotSearchDeveloperOrSiblingBundles() throws {
        try fixture { root in
            let app = root.appendingPathComponent("Mac Plaza.app")
            let resources = app.appendingPathComponent("Contents/Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": "local.macplaza.resource-test", "CFBundleExecutable": "MacPlaza", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
            let bundle = try XCTUnwrap(Bundle(url: app))
            let sibling = root.appendingPathComponent("MacPlaza_MacPlaza.bundle/Audio")
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            try Data("must not use developer resources".utf8).write(to: sibling.appendingPathComponent("warawara-home.m4a"))
            let roots = PlazaResources.roots(bundle: bundle, executableURL: app.appendingPathComponent("Contents/MacOS/MacPlaza"))
            XCTAssertTrue(roots.allSatisfy { $0.path.hasPrefix(app.path + "/") })
            XCTAssertNil(PlazaResources.url(for: "warawara-home", extension: "m4a", directory: "Audio", roots: roots))
            let included = resources.appendingPathComponent("Audio")
            try FileManager.default.createDirectory(at: included, withIntermediateDirectories: true)
            let song = included.appendingPathComponent("miiverse.m4a")
            try Data("included recording".utf8).write(to: song)
            XCTAssertEqual(PlazaResources.url(for: "miiverse", extension: "m4a", directory: "Audio", roots: roots), song)
        }
    }

    @MainActor func testDevelopmentResourcesAndRendererAssetsStillResolve() throws {
        XCTAssertNotNil(PlazaResources.url(for: "SOURCE", extension: "txt", directory: "Audio"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: FFLSurface.assetRoot.appendingPathComponent("index.html").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: FFLSurface.assetRoot.appendingPathComponent("vendor/ffl-emscripten.wasm").path))
    }

    @MainActor func testMissingSoundtracksSurviveRepeatedAudioInterruptionsAndMenuChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let audio = PlazaAudio(resourceRoots: [root])
        defer { audio.update(enabled: false, allowPreview: false) }
        for track in [PlazaAudio.Track.plaza, .maker, .friends, .settings, .writing, .miiverse] {
            audio.update(enabled: true, volume: 0, track: track)
            XCTAssertTrue(audio.isBackgroundPlaying, "Missing soundtrack must use synthesized audio")
            for _ in 0..<3 {
                audio.releaseForAudioInterruption()
                audio.update(enabled: false, volume: 0, track: track, allowPreview: false)
                XCTAssertTrue(audio.backgroundPlayback.isEmpty)
                audio.update(enabled: true, volume: 0, track: track)
                XCTAssertTrue(audio.isBackgroundPlaying, "Resuming after other audio must not trap")
            }
        }
        audio.releaseForAudioInterruption()
        audio.update(enabled: false, volume: 0, allowPreview: false)
        XCTAssertFalse(audio.isBackgroundPlaying)
    }
}
