import XCTest
import AppKit
import CryptoKit
import PlazaCore
@testable import MacPlaza

final class ResourcePackTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func fixture(_ root: URL, musicData: Data? = nil, edit: ((inout [String: Any]) -> Void)? = nil,
                         corrupt: Bool = false, trailing: Bool = false, truncate: Bool = false) throws -> URL {
        let face = Data("FFRA".utf8) + Data(repeating: 0, count: 1020)
        let body = try JSONSerialization.data(withJSONObject: ["version": 1, "models": [[:], [:]],
            "animations": Array(repeating: ["name": "Walk", "frames": 30, "loop": true] as [String: Any], count: 6),
            "texture": ["data": [0, 0, 0, 255]]])
        var files = [("faces", "FFLResHigh.dat", "", face), ("bodies", "plaza-body.json", "", body)]
        if let musicData { files.append(("music", "plaza.wav", "warawara-home", musicData)) }
        var manifest: [String: Any] = ["version": 1, "name": "Test resources", "entries": files.map { kind, file, role, bytes -> [String: Any] in
            var entry: [String: Any] = ["kind": kind, "file": file, "name": file, "size": bytes.count,
             "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
            if !role.isEmpty { entry["role"] = role }
            return entry
        }]
        edit?(&manifest)
        let json = try JSONSerialization.data(withJSONObject: manifest)
        var data = Data("PLAZAPK1".utf8)
        var length = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(json)
        for file in files { data.append(file.3) }
        if corrupt { data[data.count - 1] ^= 1 }
        if trailing { data.append(0) }
        if truncate { data.removeLast() }
        let url = root.appendingPathComponent(UUID().uuidString + ".plazapack")
        try data.write(to: url)
        return url
    }
    func testImportPreservesPersonalDataAndBacksUpRenderer() throws {
        let root = try temporary(), source = try fixture(root)
        let pack = try PlazaResourcePack.prepare(source); defer { pack.discard() }
        let destination = root.appendingPathComponent("SavedPlaza")
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("Renderer"), withIntermediateDirectories: true)
        let sentinel = Data("Saved Miis, preferences and notes".utf8)
        let document = destination.appendingPathComponent("plaza.json")
        try sentinel.write(to: document)
        let old = Data("previous face resource".utf8)
        let faces = destination.appendingPathComponent("Renderer/FFLResHigh.dat")
        try old.write(to: faces)
        let result = try PlazaResourcePack.install(pack, at: destination)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: document), sentinel)
        XCTAssertEqual(try Data(contentsOf: result.backup.appendingPathComponent("Renderer/FFLResHigh.dat")), old)
        XCTAssertEqual(try Data(contentsOf: faces), try Data(contentsOf: pack.faces))
        XCTAssertEqual(pack.animationCount, 6)
    }
    func testBrokenAndUnsupportedPacksCannotBePrepared() throws {
        let root = try temporary()
        for url in [try fixture(root, corrupt: true), try fixture(root, trailing: true), try fixture(root, truncate: true),
                    try fixture(root, edit: { $0["version"] = 999 }),
                    try fixture(root, edit: { manifest in
                        var entries = manifest["entries"] as! [[String: Any]]
                        entries[0]["file"] = "../FFLResHigh.dat"; manifest["entries"] = entries
                    }),
                    try fixture(root, edit: { manifest in
                        var entries = manifest["entries"] as! [[String: Any]]
                        entries.append(entries[0]); manifest["entries"] = entries
                    }),
                    try fixture(root, edit: { manifest in
                        var entries = manifest["entries"] as! [[String: Any]]
                        entries[0]["size"] = Int.max; manifest["entries"] = entries
                    })] {
            XCTAssertThrowsError(try PlazaResourcePack.prepare(url))
        }
    }
    func testFailureAfterWritesRestoresOldResourcesAndRemovesNewFiles() throws {
        let root = try temporary(), source = try fixture(root)
        let pack = try PlazaResourcePack.prepare(source); defer { pack.discard() }
        let destination = root.appendingPathComponent("SavedPlaza")
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("Renderer"), withIntermediateDirectories: true)
        let faces = destination.appendingPathComponent("Renderer/FFLResHigh.dat"), old = Data("old".utf8)
        try old.write(to: faces)
        XCTAssertThrowsError(try PlazaResourcePack.install(pack, at: destination) { index in
            if index == 3 { throw CocoaError(.fileWriteOutOfSpace) }
        })
        XCTAssertEqual(try Data(contentsOf: faces), old)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Renderer/plaza-body.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Renderer/resource-info.txt").path))
    }
    func testSymlinkDestinationsCannotRedirectImport() throws {
        let root = try temporary(), pack = try PlazaResourcePack.prepare(fixture(root)); defer { pack.discard() }
        for name in ["Renderer", "Music", "ResourcePackBackups"] {
            let destination = root.appendingPathComponent(UUID().uuidString)
            let external = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent(name), withDestinationURL: external)
            XCTAssertThrowsError(try PlazaResourcePack.install(pack, at: destination))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
        }
    }
    @MainActor func testMusicReplacementPersistsAndRollbackPreservesOtherTracks() throws {
        let root = try temporary(), source = root.appendingPathComponent("Previous.wav")
        let audio = PlazaAudio.loop(); try audio.write(to: source)
        let library = PlazaMusicLibrary(directory: root.appendingPathComponent("Music"))
        try library.install(source, for: .plaza); try library.install(source, for: .friends)
        let previous = try XCTUnwrap(library.url(for: .plaza)), friends = try XCTUnwrap(library.url(for: .friends))
        let manifest = library.directory.appendingPathComponent("music.json"), original = try Data(contentsOf: manifest)
        let pack = try PlazaResourcePack.prepare(fixture(root, musicData: audio)); defer { pack.discard() }
        XCTAssertThrowsError(try PlazaResourcePack.install(pack, at: root) { index in
            if index == 6 { throw CocoaError(.fileWriteOutOfSpace) }
        })
        XCTAssertEqual(try Data(contentsOf: manifest), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).count, 3)
        let result = try PlazaResourcePack.install(pack, at: root)
        pack.discard(); try FileManager.default.removeItem(at: source)
        library.reloadInstalled()
        XCTAssertEqual(result.musicCount, 1)
        XCTAssertEqual(library.url(for: .friends), friends)
        XCTAssertNotEqual(library.url(for: .plaza), previous)
        XCTAssertTrue(FileManager.default.fileExists(atPath: previous.path))
        let persistent = PlazaMusicLibrary(directory: library.directory)
        XCTAssertEqual(persistent.url(for: .plaza), library.url(for: .plaza))
        try MusicFileValidation.validate(XCTUnwrap(persistent.url(for: .plaza)))
        XCTAssertThrowsError(try PlazaResourcePack.prepare(fixture(root, musicData: Data("not audio".utf8))))
    }
    @MainActor func testOriginalPackRendersAndRestoresAllMusicWithPersistentCopies() async throws {
        guard let path = ProcessInfo.processInfo.environment["PLAZA_RESOURCE_PACK_QA"] else { throw XCTSkip("Requires the private local resource pack") }
        let pack = try PlazaResourcePack.prepare(URL(fileURLWithPath: path)); defer { pack.discard() }
        XCTAssertEqual(pack.animationCount, 172); XCTAssertEqual(pack.music.count, 6)
        _ = NSApplication.shared
        let surface = FFLSurface(mode: "portrait", resource: try FFLResources.checkedData(at: pack.faces),
                                 bodyResource: try Data(contentsOf: pack.bodies), useInstalledBody: false)
        defer { surface.invalidate() }
        for gender in [0, 1] {
            var avatar = Avatar(name: "Imported Mii"); avatar.features.gender = gender
            let image = try await surface.portrait(avatar, pose: 1, width: 96, height: 144)
            XCTAssertNotNil(image.tiffRepresentation)
        }
        let root = try temporary(), library = PlazaMusicLibrary(directory: root.appendingPathComponent("Music"))
        let wave = root.appendingPathComponent("previous.wav"); try PlazaAudio.loop().write(to: wave)
        try library.install(wave, for: .plaza)
        let oldURL = try XCTUnwrap(library.url(for: .plaza))
        let oldManifest = try Data(contentsOf: library.directory.appendingPathComponent("music.json"))
        let sentinel = Data("Characters, notes and account unchanged".utf8)
        try sentinel.write(to: root.appendingPathComponent("plaza.json"))
        XCTAssertThrowsError(try PlazaResourcePack.install(pack, at: root) { index in
            if index == 11 { throw CocoaError(.fileWriteOutOfSpace) }
        })
        XCTAssertEqual(try Data(contentsOf: library.directory.appendingPathComponent("music.json")), oldManifest)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).filter { $0.hasSuffix("m4a") }.count, 0)
        let result = try PlazaResourcePack.install(pack, at: root)
        library.reloadInstalled()
        XCTAssertTrue(FFLResources(directory: root.appendingPathComponent("Renderer")).installed)
        let body = PlazaBodyResources(directory: root.appendingPathComponent("Renderer"))
        XCTAssertTrue(body.installed); XCTAssertEqual(body.originalCatalog?.clips.count, 172)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("plaza.json")), sentinel)
        XCTAssertEqual(try Data(contentsOf: result.backup.appendingPathComponent("Music/music.json")), oldManifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        pack.discard()
        let reloaded = PlazaMusicLibrary(directory: library.directory)
        for role in PlazaResourcePack.roles {
            let track = try XCTUnwrap(PlazaAudio.Track(rawValue: role)), url = try XCTUnwrap(reloaded.url(for: track))
            try MusicFileValidation.validate(url)
            XCTAssertTrue(url.path.hasPrefix(root.path)); XCTAssertNotEqual(url, oldURL)
        }
    }
}
