import XCTest
import AppKit
@testable import MacPlaza

final class WallpaperMusicTests: XCTestCase {
    @MainActor func testWallpaperMusicPlaysWithoutVisibleWindowsAndHonorsSavedControls() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer {
            model.audio.update(enabled: false, allowPreview: false)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.document.preferences.musicVolume = 0
        model.document.preferences.makerMusicVolume = 0
        model.document.preferences.ambientSound = true
        model.wallpaperEnabled = true
        model.windowVisible = false
        model.desktopVisible = false
        model.desktopInteractive = false
        model.updateAudio()
        XCTAssertTrue(model.audioEligible)
        XCTAssertTrue(model.audio.isBackgroundPlaying,"Wallpaper music continues behind other apps and Finder")
        XCTAssertFalse(model.isMoving,"A covered wallpaper still suspends rendering")

        model.otherAppFullScreen = true
        XCTAssertFalse(model.audioEligible)
        XCTAssertFalse(model.audio.isBackgroundPlaying, "Another app going full screen mutes without a visible SwiftUI surface")
        model.otherAppFullScreen = false
        XCTAssertTrue(model.audio.isBackgroundPlaying, "Returning to the desktop resumes wallpaper music")

        let custom = directory.appendingPathComponent("Custom wallpaper music.wav")
        try PlazaAudio.loop().write(to: custom)
        try model.music.install(custom, for: .plaza)
        XCTAssertTrue(model.audio.isBackgroundPlaying,"Custom imports use the wallpaper audio path too")
        model.document.preferences.ambientSound = false
        model.updateAudio()
        XCTAssertFalse(model.audio.isBackgroundPlaying,"The saved mute setting applies to wallpaper music")
        model.document.preferences.ambientSound = true
        model.updateAudio()
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.makerEditorVisible = true
        XCTAssertFalse(model.audioEligible,"A hidden maker does not play its own music")
        model.desktopMakerVisible = true
        model.updateAudio()
        XCTAssertEqual(model.musicTrack,.maker)
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.otherAppFullScreen = true
        XCTAssertFalse(model.audio.isBackgroundPlaying, "External full screen also mutes Mii Maker")
        model.otherAppFullScreen = false
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.makerEditorVisible = false
        model.desktopMakerVisible = false
        model.updateAudio()
        XCTAssertEqual(model.musicTrack,.plaza)
        XCTAssertTrue(model.audio.isBackgroundPlaying,"Closing the maker restores the wallpaper soundtrack")

        model.sessionActive = false
        model.updateAudio()
        XCTAssertFalse(model.audio.isBackgroundPlaying,"Sleep or session lock pauses music")
        model.sessionActive = true
        model.updateAudio()
        XCTAssertTrue(model.audio.isBackgroundPlaying,"Wake resumes music when enabled")
        model.document.preferences.safeMode = true
        model.updateAudio()
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.document.preferences.safeMode = false
        model.document.preferences.pauseMotion = true
        model.updateAudio()
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.document.preferences.pauseMotion = false
        model.listMode = true
        model.updateAudio()
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.listMode = false
        model.wallpaperEnabled = false
        model.updateAudio()
        XCTAssertFalse(model.audio.isBackgroundPlaying,"An ordinary hidden window remains silent")
        model.windowVisible = true
        model.updateAudio()
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        await model.flush()
        try await model.storage.endSession()
    }
}
