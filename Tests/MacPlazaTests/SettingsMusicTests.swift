import XCTest
import AppKit
import AVFoundation
import PlazaCore
@testable import MacPlaza

final class SettingsMusicTests: XCTestCase {
    @MainActor func testSettingsRecordingDecodesAndOldPreferencesUseQuietDefault() throws {
        if let url = PlazaAudio.soundtrackURL(for: .settings) {
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertTrue(player.prepareToPlay())
            XCTAssertGreaterThan(player.duration, 110)
            XCTAssertLessThan(player.duration, 125)
            XCTAssertEqual(player.numberOfChannels, 2)
        }
        let old = Data("{\"population\":160,\"pauseMotion\":false,\"pausePosts\":false,\"privatePresentation\":false,\"safeMode\":false}".utf8)
        XCTAssertNil(try JSONDecoder().decode(PlazaCore.Preferences.self, from: old).settingsMusicVolume)
        var document = PlazaDocument()
        for invalid in [-0.01, 0.36, Double.infinity, Double.nan] {
            document.preferences.settingsMusicVolume = invalid
            XCTAssertThrowsError(try document.validated())
        }
        document.preferences.settingsMusicVolume = 0.08
        XCTAssertEqual(try DocumentStorage.decode(JSONEncoder().encode(document)).preferences.settingsMusicVolume, 0.08)
    }

    @MainActor func testSettingsImportPreviewCrossfadeSuppressionAndDefaultRestoration() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false, allowPreview: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.document.preferences.musicVolume = 0
        model.document.preferences.settingsMusicVolume = 0
        model.document.preferences.ambientSound = true
        model.wallpaperEnabled = true; model.windowVisible = false; model.desktopMenuVisible = true
        model.sheet = .preferences
        // Match the Settings onAppear update after the panel owns input.
        await Task.yield()
        model.updateAudio()
        XCTAssertEqual(model.musicTrack, .settings)
        XCTAssertEqual(model.musicVolume, 0)
        XCTAssertTrue(model.audio.backgroundPlayback.contains { $0.track == .settings && $0.playing }, "Eligible: \(model.audioEligible), menu: \(model.desktopMenuVisible), playback: \(model.audio.backgroundPlayback)")
        let source = root.appendingPathComponent("My Settings music.wav")
        var wave = PlazaAudio.loop()
        wave.replaceSubrange(44..<wave.count, with: Data(repeating: 0, count: wave.count - 44))
        try wave.write(to: source)
        try model.music.stage(source, for: .settings)
        XCTAssertNil(model.music.url(for: .settings), "Choosing a replacement must not apply it before Use Music")
        try model.audio.preview(try XCTUnwrap(model.music.previewURL(for: .settings)), track: .settings, volume: 0)
        XCTAssertEqual(model.audio.previewTrack, .settings)
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.audio.stopPreview()
        model.music.applySelection(for: .settings)
        let installed = try XCTUnwrap(model.music.url(for: .settings))
        XCTAssertNotEqual(installed, source)
        XCTAssertEqual(model.audio.backgroundPlayback.first?.source, installed)
        XCTAssertNil(model.music.url(for: .plaza))
        XCTAssertNil(model.music.url(for: .maker))
        XCTAssertNil(model.music.url(for: .friends))
        let reloaded = PlazaMusicLibrary(directory: model.music.directory)
        XCTAssertEqual(reloaded.url(for: .settings), installed)
        model.otherAudioActive = true
        XCTAssertFalse(model.audio.backgroundPlayback.contains { $0.playing })
        model.otherAppCoversPlaza = true
        model.otherAudioActive = false
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.otherAppCoversPlaza = false
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.otherAppFullScreen = true
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.otherAppFullScreen = false
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.sheet = nil
        XCTAssertEqual(model.musicTrack, .plaza)
        XCTAssertTrue(Set(model.audio.backgroundPlayback.filter(\.playing).map(\.track)).isSuperset(of: [.settings, .plaza]))
        model.sheet = .preferences
        XCTAssertEqual(model.audio.backgroundPlayback.first?.track, .settings)
        XCTAssertEqual(model.audio.backgroundPlayback.first?.source, installed)
        model.music.restoreDefault(for: .settings)
        XCTAssertNil(model.music.url(for: .settings))
        XCTAssertEqual(model.audio.backgroundPlayback.first?.source, PlazaAudio.soundtrackURL(for: .settings))
        model.document.preferences.ambientSound = false
        model.updateAudio()
        model.otherAudioActive = true; model.otherAudioActive = false
        XCTAssertFalse(model.audio.isBackgroundPlaying, "Automatic resume must preserve the saved music switch")
        await model.flush()
        try await model.storage.endSession()
    }
}
