import XCTest
import AppKit
import AVFoundation
import PlazaCore
@testable import MacPlaza

@MainActor final class MiiverseThemeTests: XCTestCase {
    func testAlternateThemeHasSeparateAudioSelectionPersistsAndFallsBackSafely() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.miiverseWindow.close(); model.audio.update(enabled: false, allowPreview: false); model.scene.setMoving(false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        model.document.preferences.ambientSound = false
        model.sheet = .miiverse
        XCTAssertEqual(model.musicTrack, .miiverse)
        model.mutate { $0.preferences.miiverseAlternateTheme = true; $0.preferences.miiverseMusicVolume = 0.07 }
        let bundled = PlazaAudio.soundtrackURL(for: .miiverseAlternate)
        let fallback: PlazaAudio.Track = bundled == nil ? .miiverse : .miiverseAlternate
        XCTAssertEqual(model.musicTrack, fallback)
        let source = root.appendingPathComponent("Alternate fixture.wav")
        try PlazaAudio.loop().write(to: source)
        try model.music.install(source, for: .miiverse)
        let original = model.music.url(for: .miiverse)
        try model.music.stage(source, for: .miiverseAlternate)
        let pending = try XCTUnwrap(model.music.previewURL(for: .miiverseAlternate))
        XCTAssertEqual(model.musicTrack, fallback, "Choosing alone does not apply the file")
        XCTAssertNil(model.music.url(for: .miiverseAlternate))
        model.music.applySelection(for: .miiverseAlternate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertEqual(model.musicTrack, .miiverseAlternate)
        XCTAssertEqual(model.musicVolume, 0.07)
        XCTAssertEqual(model.music.url(for: .miiverse), original)
        XCTAssertNotEqual(model.music.url(for: .miiverseAlternate), original)
        model.windowVisible = true
        model.document.preferences.ambientSound = true
        model.document.preferences.miiverseMusicVolume = 0
        model.updateAudio()
        XCTAssertEqual(model.audio.backgroundPlayback.first?.track, .miiverseAlternate)
        XCTAssertEqual(model.audio.backgroundPlayback.first?.source, model.music.url(for: .miiverseAlternate))
        model.otherAudioActive = true
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.otherAudioActive = false
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.document.preferences.ambientSound = false; model.updateAudio()
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        await model.flush()
        let stored = try await model.storage.load()
        let saved = try XCTUnwrap(stored)
        XCTAssertEqual(saved.preferences.miiverseAlternateTheme, true)
        let reloaded = PlazaMusicLibrary(directory: model.music.directory)
        XCTAssertEqual(reloaded.url(for: .miiverseAlternate), model.music.url(for: .miiverseAlternate))
        model.mutate { $0.preferences.miiverseAlternateTheme = false }
        XCTAssertEqual(model.musicTrack, .miiverse)
        model.mutate { $0.preferences.miiverseAlternateTheme = true }
        model.music.restoreDefault(for: .miiverseAlternate)
        XCTAssertEqual(model.musicTrack, fallback)
        XCTAssertEqual(model.music.url(for: .miiverse), original)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved.preferences)) as? [String: Any])
        legacyObject.removeValue(forKey: "miiverseAlternateTheme")
        let legacy = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertNil(legacy.miiverseAlternateTheme)
        try await model.storage.endSession()
    }
    func testSuppliedAlternateTrackDecodesAndPlaysThroughTheExistingAudioSystem() async throws {
        guard let url = PlazaAudio.soundtrackURL(for: .miiverseAlternate) else {
            throw XCTSkip("The optional user-supplied recording stays local and is absent from public builds.")
        }
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 1800); XCTAssertLessThan(player.duration, 1803)
        let audio = PlazaAudio()
        defer { audio.update(enabled: false, allowPreview: false) }
        audio.update(enabled: true, volume: 0, track: .miiverseAlternate)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(audio.isBackgroundPlaying)
        XCTAssertEqual(audio.backgroundPlayback.first?.track, .miiverseAlternate)
        XCTAssertEqual(audio.backgroundPlayback.first?.source, url)
        XCTAssertGreaterThan(audio.backgroundPlayback.first?.time ?? 0, 0)
    }

}
