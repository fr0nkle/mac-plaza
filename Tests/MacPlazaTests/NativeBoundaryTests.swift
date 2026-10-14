import XCTest
import AppKit
import AVFoundation
import PlazaCore
@testable import MacPlaza

final class NativeBoundaryTests: XCTestCase {
    func testExplicitDemoDirectoryCannotRedirectAnOrdinarySavedPlaza() {
        let support = URL(fileURLWithPath: "/test/support"), temporary = URL(fileURLWithPath: "/test/temp")
        XCTAssertEqual(PlazaDataLocation.directory(arguments: ["MacPlaza", "--demo-directory=/test/isolated"], support: support, temporary: temporary).path, "/test/support/MacPlaza")
        XCTAssertEqual(PlazaDataLocation.directory(arguments: ["MacPlaza", "--demo"], support: support, temporary: temporary).path, "/test/temp/MacPlaza-Demo")
        XCTAssertEqual(PlazaDataLocation.directory(arguments: ["MacPlaza", "--demo", "--demo-directory=/test/isolated"], support: support, temporary: temporary).path, "/test/isolated")
        XCTAssertEqual(PlazaDataLocation.directory(arguments: ["MacPlaza", "--demo", "--demo-directory=relative"], support: support, temporary: temporary).path, "/test/temp/MacPlaza-Demo")
    }
    func testDrawingExportProducesActualInkAtTheExpectedCoordinates() throws {
        let strokes = [InkStroke(points: [InkPoint(0.2, 0.3), InkPoint(0.8, 0.3)])]
        let png = try InkRasterizer.png(strokes: strokes)
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, 1024)
        XCTAssertEqual(image.pixelsHigh, 1024)
        XCTAssertLessThan(png.count, 2_000_000)
        let ink = try XCTUnwrap(image.colorAt(x: 512, y: 307)?.usingColorSpace(.deviceRGB))
        let paper = try XCTUnwrap(image.colorAt(x: 512, y: 800)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(ink.redComponent, 0.3)
        XCTAssertGreaterThan(paper.redComponent, 0.95)
    }
    func testEraserIsFlattenedIntoTheExportedPNG() throws {
        let strokes = [InkStroke(points: [InkPoint(0.2, 0.3), InkPoint(0.8, 0.3)]), InkStroke(points: [InkPoint(0.5, 0.2), InkPoint(0.5, 0.4)], eraser: true)]
        let image = try XCTUnwrap(NSBitmapImageRep(data: InkRasterizer.png(strokes: strokes)))
        let erased = try XCTUnwrap(image.colorAt(x: 512, y: 307)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(erased.redComponent, 0.95)
    }
    @MainActor
    func testAppPickerValidationAndBookmarkIdentity() async throws {
        XCTAssertThrowsError(try PlazaModel.island(at: URL(fileURLWithPath: "/bin/sh")))
        XCTAssertThrowsError(try PlazaModel.island(at: FileManager.default.temporaryDirectory))
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calculator.path) else { throw XCTSkip("Calculator is not installed on this Mac") }
        let app = try PlazaModel.island(at: calculator)
        XCTAssertEqual(app.bundleID, "com.apple.calculator")
        var stale = false
        let resolved = try URL(resolvingBookmarkData: XCTUnwrap(app.bookmark), options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        XCTAssertEqual(Bundle(url: resolved)?.bundleIdentifier, app.bundleID)
        XCTAssertEqual(resolved.path, calculator.path)
    }
}

extension NativeBoundaryTests {
    func testBubbleCardsDoNotOverlapAppControlsOrEachOther() {
        for size in [CGSize(width:1060,height:470),CGSize(width:1280,height:580),CGSize(width:1600,height:900)] {
            for count in [0,8,10,12] {
                let islands=Array(PlazaLayout.slots(for:count).prefix(count))
                let points=BubblePlanner.positions(size:size,islands:islands,limit:1)
                XCTAssertLessThanOrEqual(points.count,1)
                let width=min(240,size.width*0.22)
                let cards=points.map { CGRect(x:$0.x-width/2,y:$0.y-54,width:width,height:108) }
                for (i,card) in cards.enumerated() {
                    XCTAssertFalse(islands.contains { card.intersects(PlazaLayout.controlRect(at:$0,in:size).insetBy(dx:-10,dy:-10)) })
                    for other in cards.dropFirst(i+1) { XCTAssertFalse(card.intersects(other)) }
                }
            }
        }
        XCTAssertEqual(BubblePlanner.positions(size:CGSize(width:1280,height:580),islands:Array(PlazaLayout.compactSlots),limit:1).count,1)
    }
}

extension NativeBoundaryTests {
    @MainActor
    func testThreeDimensionalRigDirectionsAndGesturesRenderDistinctly() throws {
        var a=Avatar(name:"Classic"); a.hair=1
        let front=AvatarArtwork.image(a,size:CGSize(width:256,height:384))
        let back=AvatarArtwork.image(a,direction:4,size:CGSize(width:256,height:384))
        let wave=AvatarArtwork.image(a,size:CGSize(width:256,height:384),pose:3)
        let frontData=try XCTUnwrap(front.tiffRepresentation),backData=try XCTUnwrap(back.tiffRepresentation),waveData=try XCTUnwrap(wave.tiffRepresentation)
        XCTAssertNotEqual(frontData,backData); XCTAssertNotEqual(frontData,waveData)
        XCTAssertTrue(front === AvatarArtwork.image(a,size:CGSize(width:256,height:384)))
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:frontData))
        var visible=0
        for y in stride(from:0,to:bitmap.pixelsHigh,by:4) { for x in stride(from:0,to:bitmap.pixelsWide,by:4) {
            if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.5 { visible += 1 }
        }}
        XCTAssertGreaterThan(visible,100)
        if ProcessInfo.processInfo.environment["PLAZA_RENDER_QA"] == "1" {
            let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            for (name,data) in [("Character Front",frontData),("Character Back",backData),("Character Wave",waveData)] {
                let rep=try XCTUnwrap(NSBitmapImageRep(data:data)); try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent(name+".png"))
            }
        }
    }
}

extension NativeBoundaryTests {
    @MainActor
    func testOriginalMusicIsAValidBoundedLocalWAV() throws {
        let data=PlazaAudio.loop()
        XCTAssertEqual(String(data:data.prefix(4),encoding:.utf8),"RIFF")
        XCTAssertEqual(String(data:data[8..<12],encoding:.utf8),"WAVE")
        XCTAssertLessThan(data.count,1_000_000)
        XCTAssertNotNil(NSSound(data:data))
    }
}

extension NativeBoundaryTests {
    @MainActor
    func testAuthoredHairAndExpressionCatalog() throws {
        XCTAssertEqual(HairGeometry.styles.count,132)
        XCTAssertEqual(HairGeometry.displayOrder.sorted(),Array(0..<132))
        XCTAssertEqual(HairGeometry.styles[30].shape,.bald)
        XCTAssertEqual(HairGeometry.styles[5].shape,.crop)
        XCTAssertEqual(HairGeometry.styles[28].shape,.twins)
        XCTAssertEqual(FaceDrawing.eyes.count,60)
        let gray=try XCTUnwrap(AvatarArtwork.hairs[4].usingColorSpace(.deviceRGB))
        XCTAssertEqual(gray.redComponent,gray.greenComponent,accuracy:0.001)
        let blue=try XCTUnwrap(AvatarArtwork.eyeColors[4].usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(blue.blueComponent,blue.redComponent)
        var a=Avatar(name:"Appearance");a.hair=33;a.eyes=2;a.mouth=5
        let face=AvatarArtwork.face(a)
        let texture=try XCTUnwrap(face.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(texture.pixelsWide,256);XCTAssertEqual(texture.pixelsHigh,256)
        let neutral=try XCTUnwrap(face.tiffRepresentation)
        XCTAssertNotEqual(neutral,try XCTUnwrap(AvatarArtwork.face(a,mood:.happy).tiffRepresentation))
        XCTAssertNotEqual(neutral,try XCTUnwrap(AvatarArtwork.face(a,mood:.surprised).tiffRepresentation))
        let short=try XCTUnwrap(AvatarArtwork.headshot(a).tiffRepresentation);a.hair=30
        XCTAssertNotEqual(short,try XCTUnwrap(AvatarArtwork.headshot(a).tiffRepresentation))
        if ProcessInfo.processInfo.environment["PLAZA_RENDER_QA"] == "1" {
            let ids=[33,1,44,12,0,4,9,28,18,30,64,58]
            let sheet=NSImage(size:CGSize(width:960,height:720),flipped:true) { _ in
                NSColor.white.setFill();NSRect(x:0,y:0,width:960,height:720).fill()
                for (i,id) in ids.enumerated() {
                    var sample=a;sample.hair=id;sample.eyes=[2,0,8,24,18,35,15,40,6,53,32,27][i];sample.brows=i%24;sample.mouth=[5,0,19,7,14,5,23,8,12,5,3,0][i];sample.hairColor=i%8
                    let x=CGFloat(i%4)*240,y=CGFloat(i/4)*240
                    AvatarArtwork.headshot(sample,size:CGSize(width:210,height:200)).draw(in:NSRect(x:x+15,y:y+10,width:210,height:200))
                    ("Hair \(id) · Eyes \(sample.eyes)" as NSString).draw(at:CGPoint(x:x+40,y:y+215),withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.black])
                };return true
            }
            let bitmap=try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(sheet.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/Appearance Gallery.png"))
        }
    }
}

extension NativeBoundaryTests {
    @MainActor
    func testRequestedSoundtrackDecodesForLoopingPlayback() throws {
        let url = try XCTUnwrap(PlazaAudio.soundtrackURL)
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 1830)
        XCTAssertLessThan(player.duration, 1850)
        XCTAssertEqual(player.numberOfChannels, 2)
        XCTAssertTrue(player.prepareToPlay())
    }

    @MainActor
    func testMakerSoundtrackDecodesForLoopingPlayback() throws {
        let player = try AVAudioPlayer(contentsOf: XCTUnwrap(PlazaAudio.soundtrackURL(for: .maker)))
        XCTAssertGreaterThan(player.duration, 590)
        XCTAssertLessThan(player.duration, 610)
        XCTAssertEqual(player.numberOfChannels, 2)
        XCTAssertTrue(player.prepareToPlay())
    }

    func testMusicVolumeValidationAndLegacyPreferences() throws {
        var document = PlazaDocument()
        document.preferences.musicVolume = 0.12
        XCTAssertNoThrow(try document.validated())
        for invalid in [-0.1, 0.36, Double.infinity, Double.nan] {
            document.preferences.musicVolume = invalid
            XCTAssertThrowsError(try document.validated())
        }
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{\"population\":60,\"pauseMotion\":false,\"pausePosts\":false,\"privatePresentation\":false,\"safeMode\":false}".utf8))
        XCTAssertNil(legacy.musicVolume)
        XCTAssertNil(legacy.ambientSound)
        XCTAssertNil(legacy.makerMusicVolume)
        document.preferences.musicVolume = 0.12
        document.preferences.makerMusicVolume = 0.10
        XCTAssertNoThrow(try document.validated())
        for invalid in [-0.1, 0.36, Double.infinity, Double.nan] {
            document.preferences.makerMusicVolume = invalid
            XCTAssertThrowsError(try document.validated())
        }
    }

    func testAppPreviewReadsInstalledMetadataAndHandlesDisconnectedShortcuts() throws {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard let bundle = Bundle(url: url) else { throw XCTSkip("Calculator is not installed") }
        let app = AppIsland(label: "Calculator", bundleID: "com.apple.calculator")
        let info = AppPreviewInfo(app: app, url: url)
        XCTAssertEqual(info.version, bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(info.location, "Applications")
        XCTAssertFalse(info.category.contains("public.app-category"))
        let disconnected = AppPreviewInfo(app: app, url: nil)
        XCTAssertNil(disconnected.version)
        XCTAssertNil(disconnected.location)
        XCTAssertTrue(disconnected.summary.contains("Calculator"))
    }
}
