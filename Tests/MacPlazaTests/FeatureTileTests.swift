import XCTest
import AppKit
import PlazaCore
@testable import MacPlaza

final class FeatureTileTests: XCTestCase {
    @MainActor func testFallbackFeatureCatalogIsIsolatedAndStableAcrossUnrelatedEdits() throws {
        var avatar = Avatar()
        for feature in MiiTileFeature.allCases {
            let count = feature == .eyes ? 60 : feature == .brows ? 24 : feature == .nose ? 18 : 36
            for id in 0..<count {
                avatar.eyes = min(id,59); avatar.brows = min(id,23); avatar.nose = min(id,17); avatar.mouth = min(id,35)
                let bitmap = try pixels(feature.fallback(feature.sample(from: avatar)))
                XCTAssertEqual(bitmap.colorAt(x: 0,y: 0)?.alphaComponent, 0)
                if !(feature == .brows && id == 23) { XCTAssertGreaterThan(visible(bitmap), 0, "\(feature) \(id)") }
            }
            let before = feature.sample(from: avatar)
            avatar.name = "Changed"; avatar.hair = 131; avatar.height = 1; avatar.features.eyeSize = 0; avatar.features.browY = 1
            XCTAssertEqual(before, feature.sample(from: avatar))
        }
    }
    @MainActor func testOriginalFFLFeatureTilesAreTransparentAndDistinct() async throws {
        guard let path = ProcessInfo.processInfo.environment["PLAZA_FFL_QA_RESOURCE"] else { throw XCTSkip("Requires a local FFL resource.") }
        _ = NSApplication.shared
        let surface = FFLSurface(mode: "portrait", resource: try FFLResources.checkedData(at: URL(fileURLWithPath: path)), useInstalledBody: false)
        defer { surface.invalidate() }
        let gallery = NSImage(size: CGSize(width: 576,height: 384))
        gallery.lockFocus(); NSColor.white.setFill(); NSRect(x: 0,y: 0,width: 576,height: 384).fill(); gallery.unlockFocus()
        for (column,feature) in MiiTileFeature.allCases.enumerated() {
            var results: [Data] = []
            for row in 0..<4 {
                var avatar = Avatar()
                avatar.eyes = [0,8,35,59][row]; avatar.brows = [0,10,16,22][row]
                avatar.nose = [0,4,8,17][row]; avatar.mouth = [0,10,23,35][row]
                let image = try await surface.portrait(feature.sample(from: avatar), width: 144,height: 96,feature: feature)
                let bitmap = try pixels(image)
                XCTAssertEqual(bitmap.colorAt(x: 0,y: 0)?.alphaComponent, 0)
                XCTAssertGreaterThan(visible(bitmap), 4,"\(feature) \(row) must contain its feature")
                XCTAssertLessThan(visible(bitmap), 144*96/2,"An isolated feature must not fill the tile with a head")
                results.append(try XCTUnwrap(bitmap.representation(using: .png,properties: [:])))
                gallery.lockFocus(); image.draw(in: NSRect(x: column*144,y: (3-row)*96,width: 144,height: 96)); gallery.unlockFocus()
            }
            XCTAssertEqual(Set(results).count, 4,"Distinct original styles must have distinct thumbnails")
        }
        let qa = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
        try FileManager.default.createDirectory(at: qa,withIntermediateDirectories: true)
        try XCTUnwrap(pixels(gallery).representation(using: .png,properties: [:])).write(to: qa.appendingPathComponent("Isolated FFL Features.png"))
        // A feature capture must leave the shared renderer usable for portraits.
        let portrait = try await surface.portrait(Avatar(),width:144,height:192)
        XCTAssertGreaterThan(visible(try pixels(portrait)), 100)
    }
    @MainActor private func pixels(_ image: NSImage) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
    }
    @MainActor private func visible(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            if (bitmap.colorAt(x: x,y: y)?.alphaComponent ?? 0) > 0.1 { count += 1 }
        } }
        return count
    }
}
