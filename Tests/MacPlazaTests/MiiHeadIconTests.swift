import XCTest
import AppKit
import PlazaCore
@testable import MacPlaza

@MainActor
final class MiiHeadIconTests: XCTestCase {
    func testProfileHeadsRenderTheCurrentMiisDistinctAppearance() async throws {
        _ = NSApplication.shared
        var first = Avatar(name: "Alex")
        first.hair = 33; first.hairColor = 1; first.eyes = 2
        var second = first
        second.id = UUID(); second.name = "Sam"; second.skin = 4
        second.hair = 46; second.hairColor = 7; second.glasses = true
        second.features.glassesType = 2
        XCTAssertNotEqual(MiiHeadPictures.key(for: first), MiiHeadPictures.key(for: second))
        let heads = [await MiiHeadPictures.image(first), await MiiHeadPictures.image(second)]
        let bitmaps = try heads.map { try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap($0.tiffRepresentation))) }
        XCTAssertNotEqual(try XCTUnwrap(heads[0].tiffRepresentation), try XCTUnwrap(heads[1].tiffRepresentation))
        for bitmap in bitmaps {
            XCTAssertEqual(bitmap.pixelsWide, 128)
            XCTAssertEqual(bitmap.pixelsHigh, 128)
            var visible = 0
            for y in stride(from: 0, to: 128, by: 4) {
                for x in stride(from: 0, to: 128, by: 4) {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { visible += 1 }
                }
            }
            XCTAssertGreaterThan(visible, 100, "The icon must contain the Mii's full rendered head")
        }
        if ProcessInfo.processInfo.environment["PLAZA_HEAD_ICON_QA"] == "1" {
            let gallery = NSImage(size: CGSize(width: 420, height: 220))
            gallery.lockFocus()
            NSColor(white: 0.96, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 420, height: 220).fill()
            for (index, head) in heads.enumerated() {
                let x = CGFloat(index) * 200 + 30
                head.draw(in: CGRect(x: x, y: 50, width: 140, height: 140))
                ((index == 0 ? "Alex" : "Sam") as NSString).draw(at: CGPoint(x: x + 50, y: 25), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray])
            }
            gallery.unlockFocus()
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/mii-speaking-head-icons.png")
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(gallery.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
        }
    }
}
