import XCTest
import AppKit
@testable import MacPlaza

final class DesktopPlazaTests: XCTestCase {
    @MainActor
    func testWallpaperControlsOwnTheirEntireMouseHitAreas() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "MacPlaza.WallpaperHitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = PlazaModel(directory: directory)
        let controller = DesktopPlazaController(model: model, defaults: defaults)
        model.desktop = controller
        let main = NSWindow(contentRect: NSRect(x: 90, y: 100, width: 1060, height: 720),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        model.window = main
        defer {
            controller.disable(showWindow: false)
            controller.shutdown()
            main.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.mutate { $0.preferences.rotatingHomeScreen = false }
        model.document.preferences.pauseMotion = true
        controller.enable(activate: false)
        let host = try XCTUnwrap(controller.window?.contentView)
        // Let SwiftUI install the actual desktop view, including its native renderer.
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let insets = model.desktopInsets
        let width = host.bounds.width - insets.leading - insets.trailing
        let height = host.bounds.height - insets.top - insets.bottom
        func assertControlHit(_ x: CGFloat, _ y: CGFloat, _ name: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
            let fromTop = insets.top + y
            let point = NSPoint(x: insets.leading + x,
                                y: host.isFlipped ? fromTop : host.bounds.height - fromTop)
            let hit = try XCTUnwrap(host.hitTest(host.convert(point, to: host.superview)), name, file: file, line: line)
            XCTAssertTrue(hit is PlazaControlHostingView,
                          "\(name) fell through to \(type(of: hit))", file: file, line: line)
            XCTAssertTrue(hit.acceptsFirstMouse(for: nil), name, file: file, line: line)
            XCTAssertFalse(hit.mouseDownCanMoveWindow, "\(name) must not drag the window", file: file, line: line)
        }
        // Sample empty label space as well as the glyph/text, not just AXPress.
        try assertControlHit(width - 18 - 78 + 5, 18 + 5, "Mii Maker corner")
        try assertControlHit(width - 18 - 39, 18 + 35, "Mii Maker center")
        try assertControlHit(width - 18 - 78 - 12 - 39, 18 + 35, "Settings center")
        try assertControlHit(width - 18 - 78 - 12 - 78 - 12 - 39, 18 + 35, "Friends center")
        try assertControlHit(width - 18 - 78 - 12 - 78 - 12 - 78 + 5, 18 + 5, "Friends corner")
        try assertControlHit(width - 18 - 374 + 5, 18 + 5, "Change Apps corner")
        try assertControlHit(width - 18 - 374 + 52, 18 + 35, "Change Apps center")
        func captureControls(_ name: String) throws {
            guard ProcessInfo.processInfo.environment["PLAZA_HOME_QA"] == "1" else { return }
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".qa/\(name).png")
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        }
        try captureControls("Home Screen Controls")
        model.beginChangingApps()
        XCTAssertTrue(model.editing)
        model.scene.finishEntrance()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        try assertControlHit(width - 18 - 374 + 50, 18 + 70 + 10 + 21, "Add App")
        try assertControlHit(width - 18 - 30, 18 + 70 + 10 + 21, "Undo app change")
        for (index, slot) in PlazaLayout.slots(for: model.visibleApps.count).prefix(model.visibleApps.count).enumerated() {
            try assertControlHit(slot.x * width, slot.y * height, "App drag surface \(index)")
            try assertControlHit(slot.x * width, slot.y * height + PlazaLayout.tileSize(in: CGSize(width: width, height: height)) / 2 + 23,
                                 "App drag label \(index)")
        }
        try captureControls("Change Apps Controls")
        model.editing = false
        XCTAssertFalse(model.editing)
        try assertControlHit(20 + 5 + 3, height - 20 - 5 - 3, "Zoom out corner")
        try assertControlHit(20 + 5 + 15, height - 20 - 5 - 15, "Zoom out center")
        func navigation(in view: NSView) -> PlazaNavigationInput.NavigationView? {
            if let result = view as? PlazaNavigationInput.NavigationView { return result }
            return view.subviews.lazy.compactMap { navigation(in: $0) }.first
        }
        let input = try XCTUnwrap(navigation(in: host))
        input.zoom = 1.3
        input.canPan = true
        var pans = 0
        input.onPan = { _ in pans += 1 }
        func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws -> NSEvent {
            let local = NSPoint(x: insets.leading + x,
                                y: host.isFlipped ? insets.top + y : host.bounds.height - insets.top - y)
            return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: host.convert(local, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: controller.window!.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        // Slight pointer motion while clicking a HUD control must not start a pan.
        let x: CGFloat = 40, y = height - 40
        XCTAssertNotNil(input.handle(try mouse(.leftMouseDown, x: x, y: y)))
        XCTAssertNotNil(input.handle(try mouse(.leftMouseDragged, x: x + 10, y: y)))
        XCTAssertNotNil(input.handle(try mouse(.leftMouseUp, x: x + 10, y: y)))
        XCTAssertEqual(pans, 0)
        // Camera dragging still works on the floor outside the control surfaces.
        XCTAssertNotNil(input.handle(try mouse(.leftMouseDown, x: width / 2, y: height / 2)))
        XCTAssertNil(input.handle(try mouse(.leftMouseDragged, x: width / 2 + 20, y: height / 2)))
        XCTAssertNil(input.handle(try mouse(.leftMouseUp, x: width / 2 + 20, y: height / 2)))
        XCTAssertEqual(pans, 1)
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor
    func testWallpaperAppDragMovesOnlyOnReleaseAndCancelsOutside() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Optional local QA fixture is copied before loading; the source save is
        // never opened for writing by this test.
        if let fixture = ProcessInfo.processInfo.environment["PLAZA_WALLPAPER_TEST_DOCUMENT"] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture),
                                            to: directory.appendingPathComponent("plaza.json"))
        }
        let model = PlazaModel(directory: directory)
        let suite = "MacPlaza.WallpaperDragTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = DesktopPlazaController(model: model, defaults: defaults)
        model.desktop = controller
        let main = NSWindow(contentRect: NSRect(x: 90, y: 100, width: 1060, height: 720),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false; model.window = main
        defer {
            controller.disable(showWindow: false); controller.shutdown(); main.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.mutate { $0.preferences.rotatingHomeScreen = false }
        model.document.preferences.pauseMotion = true
        controller.enable(activate: false); model.beginChangingApps(); model.scene.finishEntrance()
        try await Task.sleep(for: .milliseconds(150))
        let host = try XCTUnwrap(controller.window?.contentView)
        host.layoutSubtreeIfNeeded()
        func apps(in view: NSView) -> [PlazaAppHostingView] {
            if let app = view as? PlazaAppHostingView { return [app] }
            return view.subviews.flatMap { apps(in: $0) }
        }
        let original = model.document.apps
        let originalDocument = model.document
        let views = apps(in: host)
        XCTAssertEqual(views.count, original.count)
        let source = try XCTUnwrap(views.first { $0.appID == original[0].id })
        let destination = try XCTUnwrap(views.first { $0.appID == original.last?.id })
        func center(_ view: NSView) -> NSPoint {
            view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        }
        func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: controller.window!.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        var clicks = 0
        source.selectApp = { clicks += 1 }
        source.beginDrag(at: center(source))
        source.updateDrag(at: center(source))
        source.endDrag(at: center(source))
        XCTAssertEqual(clicks, 1, "A click must still open app details")
        source.mouseDown(with: try event(.leftMouseDown, at: center(source)))
        source.mouseDragged(with: try event(.leftMouseDragged, at: center(destination)))
        XCTAssertTrue(source.dragging)
        XCTAssertEqual(model.document.apps, original, "Hovering cannot save or consume Undo")
        source.mouseUp(with: try event(.leftMouseUp, at: center(destination)))
        XCTAssertEqual(model.document.apps, Array(original.dropFirst()) + [original[0]])
        XCTAssertEqual(clicks, 1, "Dropping must not open app details")
        XCTAssertFalse(source.dragging); XCTAssertEqual(source.alphaValue, 1)
        await model.flush()
        let reorderedSave = try await model.storage.load()
        XCTAssertEqual(reorderedSave?.apps, model.document.apps)
        model.undoLayout(); XCTAssertEqual(model.document.apps, original)
        try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
        // Reverse direction, starting from the label rather than the icon.
        let label = destination.convert(NSPoint(x: destination.bounds.midX,
            y: destination.isFlipped ? destination.bounds.maxY - 8 : destination.bounds.minY + 8), to: nil)
        destination.mouseDown(with: try event(.leftMouseDown, at: label))
        destination.mouseDragged(with: try event(.leftMouseDragged, at: center(source)))
        destination.mouseUp(with: try event(.leftMouseUp, at: center(source)))
        XCTAssertEqual(model.document.apps, [original.last!] + Array(original.dropLast()))
        model.undoLayout()
        XCTAssertEqual(model.document, originalDocument)
        try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded()
        let outside = NSPoint(x: -100, y: -100)
        source.beginDrag(at: center(source)); source.updateDrag(at: outside); source.endDrag(at: outside)
        XCTAssertEqual(model.document.apps, original)
        source.beginDrag(at: center(source)); source.updateDrag(at: center(destination))
        model.editing = false
        try await Task.sleep(for: .milliseconds(150))
        source.endDrag(at: center(destination))
        XCTAssertEqual(model.document.apps, original, "Closing Change Apps must cancel a held drag")
        XCTAssertFalse(source.dragging)
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(model.document, originalDocument)
        await model.flush()
        let restored = try await model.storage.load()
        XCTAssertEqual(restored, originalDocument)
        try await model.storage.endSession()
    }

    @MainActor
    func testWallpaperInteractionEscapeAndWindowRestoration() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "MacPlaza.WallpaperTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = PlazaModel(directory: directory)
        let controller = DesktopPlazaController(model: model, defaults: defaults)
        model.desktop = controller
        let main = NSWindow(contentRect: NSRect(x: 90, y: 100, width: 1060, height: 720),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        model.window = main
        defer {
            controller.disable(showWindow: false)
            controller.shutdown()
            main.close()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.mutate { $0.preferences.rotatingHomeScreen = false }
        model.loginEnabled = false // Isolate this test from this Mac's login registration.
        model.document.preferences.musicVolume = 0
        model.document.preferences.makerMusicVolume = 0
        model.document.preferences.settingsMusicVolume = 0
        let originalFrame = main.frame
        let originalStyle = main.styleMask

        controller.enable()
        let wallpaper = try XCTUnwrap(controller.window)
        XCTAssertTrue(model.wallpaperEnabled)
        XCTAssertTrue(model.desktopInteractive, "Wallpaper must accept clicks immediately")
        XCTAssertFalse(wallpaper.ignoresMouseEvents)
        XCTAssertTrue(wallpaper.canBecomeKey)
        XCTAssertTrue(try XCTUnwrap(wallpaper.contentView).acceptsFirstMouse(for: nil))
        XCTAssertEqual(wallpaper.frame, DesktopPlazaController.targetScreen?.frame)
        XCTAssertTrue(model.audioEligible)
        XCTAssertTrue(model.audio.isBackgroundPlaying,"Enabling wallpaper starts the selected soundtrack")
        XCTAssertTrue(defaults.bool(forKey: DesktopPlazaController.preferenceKey))
        XCTAssertTrue(wallpaper.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(wallpaper.collectionBehavior.contains(.fullScreenAuxiliary))

        controller.interact()
        XCTAssertTrue(controller.window === wallpaper, "Changing input mode must reuse the rendering window")
        XCTAssertTrue(model.desktopInteractive)
        XCTAssertTrue(wallpaper.canBecomeKey)
        XCTAssertFalse(wallpaper.ignoresMouseEvents)
        XCTAssertGreaterThan(wallpaper.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertLessThan(wallpaper.level.rawValue, NSWindow.Level.normal.rawValue)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        await Task.yield()
        XCTAssertTrue(model.desktopInteractive, "Switching apps must not disable wallpaper input")

        // Escape from a companion editor is left for that editor to handle.
        let editorEscape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: main.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        XCTAssertNotNil(controller.handleKeyEvent(editorEscape))
        XCTAssertTrue(model.desktopInteractive)
        model.previewAppID = UUID()
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: wallpaper.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        XCTAssertNil(controller.handleKeyEvent(escape))
        XCTAssertTrue(model.wallpaperEnabled)
        XCTAssertFalse(model.desktopInteractive)
        XCTAssertTrue(wallpaper.ignoresMouseEvents)
        XCTAssertFalse(wallpaper.canBecomeKey)
        XCTAssertLessThan(wallpaper.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertNil(model.previewAppID)

        // Closing the ordinary window must not suspend a visible desktop surface.
        model.windowVisible = false
        model.desktopVisible = true
        XCTAssertTrue(model.isMoving)
        model.desktopVisible = false
        XCTAssertFalse(model.isMoving)
        controller.interact()
        model.sessionActive = false
        XCTAssertTrue(model.desktopInteractive, "Sleep pauses motion without disabling input after wake")
        XCTAssertFalse(model.isMoving)
        model.sessionActive = true

        model.sheet = .preferences
        XCTAssertFalse(model.desktopInteractive)
        XCTAssertFalse(main.isVisible)
        XCTAssertEqual(controller.menuWindow?.identifier?.rawValue, "MacPlazaDesktopSettings")
        XCTAssertTrue(model.wallpaperEnabled)
        model.desktopVisible = true
        XCTAssertTrue(model.isMoving, "Settings keeps the visible wallpaper crowd moving")
        model.sheet = nil
        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(model.desktopInteractive, "Dismissing an editor restores direct wallpaper input")
        model.sheet = .preferences
        model.search = "hidden apps"
        model.listMode = true
        model.page = 5
        model.previewAppID = UUID()
        model.beginChangingApps()
        XCTAssertNil(model.sheet)
        XCTAssertTrue(model.editing)
        XCTAssertTrue(model.desktopInteractive, "Changing apps from Settings restores wallpaper input")
        XCTAssertFalse(main.isVisible)
        XCTAssertFalse(model.listMode)
        XCTAssertEqual(model.search, "")
        XCTAssertEqual(model.page, 0)
        XCTAssertNil(model.previewAppID)
        model.sheet = .preferences
        model.returnToPlaza()
        XCTAssertNil(model.sheet)
        XCTAssertTrue(model.desktopInteractive)
        XCTAssertTrue(model.editing, "Back from shortcut menus preserves the active editor")
        XCTAssertTrue(controller.window === wallpaper, "Back must reuse the wallpaper renderer")
        controller.returnToDesktop(activateFinder: false)
        model.sheet = .preferences
        model.editing = true
        model.returnToPlaza()
        XCTAssertTrue(model.desktopInteractive, "Back also resumes a plaza opened from a menu while Finder owned input")
        XCTAssertTrue(model.editing, "Resuming input must not reset the editor")
        XCTAssertFalse(main.isVisible)
        model.editing = false
        model.sheet = .characters
        let maker=try XCTUnwrap(controller.menuWindow)
        XCTAssertTrue(maker.isVisible,"Mii Maker opens directly over the wallpaper")
        XCTAssertFalse(main.isVisible,"Opening Mii Maker must not show the companion placeholder")
        XCTAssertTrue(controller.window === wallpaper)
        XCTAssertTrue(wallpaper.isVisible)
        XCTAssertGreaterThan(wallpaper.level.rawValue,Int(CGWindowLevelForKey(.desktopIconWindow)),"The plaza must stay above Finder's desktop icons")
        XCTAssertGreaterThan(maker.level.rawValue,wallpaper.level.rawValue)
        XCTAssertFalse(model.desktopInteractive)
        XCTAssertTrue(wallpaper.ignoresMouseEvents,"Only the maker panel receives input")
        model.desktopVisible=true
        XCTAssertTrue(model.isMoving,"A windowed maker keeps the visible wallpaper crowd moving")
        XCTAssertTrue(maker.styleMask.contains(.resizable))
        XCTAssertTrue(maker.collectionBehavior.contains(.fullScreenPrimary))
        controller.windowWillEnterFullScreen(Notification(name:NSWindow.willEnterFullScreenNotification,object:maker))
        XCTAssertFalse(model.isMoving,"Full-screen Mii Maker suspends the wallpaper")
        controller.windowDidExitFullScreen(Notification(name:NSWindow.didExitFullScreenNotification,object:maker))
        XCTAssertTrue(model.isMoving,"Leaving full screen resumes the visible wallpaper")
        model.document.preferences.pauseMotion=true
        XCTAssertFalse(model.isMoving,"Opening Mii Maker must respect Pause Motion")
        model.document.preferences.pauseMotion=false
        model.desktopMenuVisible=true
        model.windowVisible=false
        XCTAssertTrue(model.audioEligible,"Mii Maker music remains eligible without the companion window")
        model.makerEditorVisible=true
        model.updateAudio()
        model.sheet = nil
        XCTAssertNil(controller.menuWindow)
        XCTAssertFalse(model.desktopMenuVisible)
        XCTAssertFalse(model.makerEditorVisible,"Closing the maker clears editor audio before tearing down its panel")
        XCTAssertTrue(Set(model.audio.backgroundPlayback.filter(\.playing).map(\.track)).isSuperset(of: [.maker, .plaza]),"Closing the feature editor must retain both sides of the crossfade")
        XCTAssertTrue(model.audioEligible,"Leaving Mii Maker resumes plaza music on the wallpaper")
        XCTAssertFalse(main.isVisible)
        XCTAssertTrue(model.desktopInteractive, "Leaving Mii Maker restores direct wallpaper input")
        // XCTest has a prohibited activation policy; key eligibility can be
        // checked here, while actual keyboard focus is verified in the app.
        XCTAssertTrue(wallpaper.canBecomeKey,"Keyboard controls return to the plaza")
        model.sheet = .characters
        let closeMaker=try XCTUnwrap(controller.menuWindow)
        XCTAssertFalse(controller.windowShouldClose(closeMaker))
        XCTAssertNil(model.sheet)
        XCTAssertNil(controller.menuWindow,"The panel close button returns to the same plaza")
        XCTAssertTrue(wallpaper.isVisible)
        model.sheet = .characters
        model.sheet = .preferences
        XCTAssertEqual(controller.menuWindow?.title, "Settings", "Settings replaces the maker with another overlay")
        XCTAssertFalse(main.isVisible)
        model.sheet = nil
        controller.returnToDesktop(activateFinder: false)
        model.sheet = .characters
        XCTAssertGreaterThan(wallpaper.level.rawValue,Int(CGWindowLevelForKey(.desktopIconWindow)))
        model.sheet = nil
        XCTAssertFalse(model.desktopInteractive,"Closing Mii Maker preserves passive desktop mode")
        XCTAssertLessThan(wallpaper.level.rawValue,Int(CGWindowLevelForKey(.desktopIconWindow)))
        model.sheet = .preferences
        model.sheet = nil
        XCTAssertFalse(model.desktopInteractive, "An editor must preserve an explicit return to Finder")

        controller.disable()
        XCTAssertFalse(model.wallpaperEnabled)
        XCTAssertNil(controller.window)
        XCTAssertFalse(defaults.bool(forKey: DesktopPlazaController.preferenceKey))
        XCTAssertEqual(main.frame, originalFrame)
        XCTAssertEqual(main.styleMask, originalStyle)
        XCTAssertTrue(main.isVisible)
        // Login startup always restores wallpaper, even if the last session used a window.
        let keyWindowBeforeRestore = NSApp.keyWindow
        model.loginEnabled = true
        controller.restoreIfNeeded()
        XCTAssertTrue(model.wallpaperEnabled)
        XCTAssertTrue(model.desktopInteractive)
        XCTAssertFalse(try XCTUnwrap(controller.window).ignoresMouseEvents)
        XCTAssertFalse(try XCTUnwrap(controller.window).isKeyWindow, "Startup must not steal keyboard focus")
        XCTAssertTrue(NSApp.keyWindow === keyWindowBeforeRestore || NSApp.keyWindow == nil)
        await model.flush()
        try await model.storage.endSession()
    }
}
