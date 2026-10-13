import XCTest
import AppKit
import AVFoundation
import PlazaCore
@testable import MacPlaza

final class FriendsMenuTests: XCTestCase {
    @MainActor func testFriendsPanelReusesWallpaperAndPreservesSimulationAndInput() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "MacPlaza.FriendsMenuTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = PlazaModel(directory: directory)
        let controller = DesktopPlazaController(model: model, defaults: defaults)
        model.desktop = controller
        let main = NSWindow(contentRect: NSRect(x: 90, y: 100, width: 1060, height: 720),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
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
        model.document.preferences.makerMusicVolume = 0
        model.document.preferences.friendsMusicVolume = 0
        model.document.preferences.settingsMusicVolume = 0
        model.document.preferences.pauseMotion = false
        controller.enable(activate: false)
        let wallpaper = try XCTUnwrap(controller.window)
        let rendererHost = try XCTUnwrap(wallpaper.contentView)
        model.sheet = .friends
        let panel = try XCTUnwrap(controller.menuWindow)
        XCTAssertEqual(panel.title, "Friends")
        XCTAssertEqual(panel.identifier?.rawValue, "MacPlazaDesktopFriends")
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(wallpaper.contentView === rendererHost, "Opening Friends must retain the wallpaper renderer")
        XCTAssertTrue(wallpaper.ignoresMouseEvents)
        model.desktopVisible = true
        model.desktopMenuVisible = true
        model.windowVisible = false
        XCTAssertEqual(model.isMoving, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        XCTAssertEqual(model.musicTrack, .friends)
        XCTAssertTrue(model.audioEligible)
        model.updateAudio()
        XCTAssertTrue(model.audio.backgroundPlayback.contains { $0.track == .friends && $0.playing })
        model.otherAudioActive = true
        XCTAssertFalse(model.audio.isBackgroundPlaying, "Friends music must respect other audio and calls")
        model.otherAudioActive = false
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.document.preferences.pauseMotion = true
        XCTAssertFalse(model.isMoving)
        model.document.preferences.pauseMotion = false
        // Switching directly between menus must never reveal the ordinary window.
        model.sheet = .characters
        XCTAssertEqual(controller.menuWindow?.title, "Mii Maker")
        XCTAssertEqual(model.musicTrack, .maker)
        XCTAssertTrue(wallpaper.contentView === rendererHost)
        model.sheet = .preferences
        XCTAssertEqual(controller.menuWindow?.title, "Settings")
        XCTAssertEqual(controller.menuWindow?.identifier?.rawValue, "MacPlazaDesktopSettings")
        XCTAssertEqual(model.musicTrack, .settings)
        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(wallpaper.contentView === rendererHost)
        model.sheet = .friends
        let reopened = try XCTUnwrap(controller.menuWindow)
        XCTAssertEqual(reopened.title, "Friends")
        XCTAssertFalse(controller.windowShouldClose(reopened))
        XCTAssertNil(model.sheet)
        XCTAssertNil(controller.menuWindow)
        XCTAssertTrue(model.desktopInteractive)
        XCTAssertFalse(main.isVisible)
        XCTAssertEqual(model.musicTrack, .plaza)
        // Closing from passive desktop mode must restore that original state.
        controller.returnToDesktop(activateFinder: false)
        model.sheet = .friends
        model.sheet = nil
        XCTAssertFalse(model.desktopInteractive)
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor func testFriendsAssignmentsRetainLiveStatusAndUseLibraryAppearance() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer { model.audio.update(enabled: false); try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        model.social.preview()
        let friend = try XCTUnwrap(model.social.friends.first { $0.temporaryAvatar == true && $0.discordID != nil })
        let avatar = try XCTUnwrap(model.document.avatars.first)
        model.social.assignMii(avatar.id, to: friend.id)
        let assigned = try XCTUnwrap(model.social.friends.first { $0.id == friend.id })
        XCTAssertEqual(model.social.assignedMiiID(for: assigned), avatar.id)
        XCTAssertEqual(assigned.avatar.name, friend.displayName, "Assigned Miis retain the friend's identity")
        XCTAssertEqual(assigned.avatar.features, avatar.features)
        XCTAssertEqual(assigned.avatar.hair, avatar.hair)
        XCTAssertEqual(assigned.presence, friend.presence)
        XCTAssertEqual(assigned.activities, friend.activities)
        XCTAssertEqual(assigned.customStatus, friend.customStatus)
        XCTAssertEqual(assigned.locallyAssignedAvatar, true)
        model.social.assignMii(nil, to: friend.id)
        XCTAssertNil(model.social.assignedMiiID(for: assigned))
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor func testBundledFriendsMusicIsPlayableAndVolumeIsBackwardCompatible() throws {
        let url = try XCTUnwrap(PlazaAudio.soundtrackURL(for: .friends))
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertTrue(player.prepareToPlay())
        XCTAssertGreaterThan(player.duration, 140)
        XCTAssertLessThan(player.duration, 155)
        let legacy = try JSONDecoder().decode(PlazaCore.Preferences.self,
            from: Data("{\"population\":160,\"pauseMotion\":false,\"pausePosts\":false,\"privatePresentation\":false,\"safeMode\":false}".utf8))
        XCTAssertNil(legacy.friendsMusicVolume)
        var document = PlazaDocument()
        for invalid in [Double.nan, .infinity, -0.01, 0.36] {
            document.preferences.friendsMusicVolume = invalid
            XCTAssertThrowsError(try document.validated())
        }
        document.preferences.friendsMusicVolume = 0.1
        XCTAssertEqual(try document.validated().preferences.friendsMusicVolume, 0.1)
    }
}
