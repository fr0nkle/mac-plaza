import Foundation
import CryptoKit

/// One bounded data file: magic, little-endian manifest length, JSON, then payloads.
/// No executable content, archive extraction, paths or network requests are used.
enum PlazaResourcePack {
    static let magic = Data("PLAZAPK1".utf8)
    static let maximumSize = 512 * 1024 * 1024
    static let roles = Set(["warawara-home", "mii-maker", "friends-menu", "system-settings", "note-writing", "miiverse"])
    struct Entry: Codable, Sendable {
        let kind: String
        let file: String
        let role: String?
        let name: String
        let size: Int
        let sha256: String
    }
    struct Manifest: Codable, Sendable {
        let version: Int
        let name: String
        let entries: [Entry]
    }
    struct Prepared: Sendable {
        let directory: URL
        let manifest: Manifest
        let animationCount: Int
        var music: [Entry] { manifest.entries.filter { $0.kind == "music" } }
        func url(for entry: Entry) -> URL { directory.appendingPathComponent(entry.file) }
        var faces: URL { url(for: manifest.entries.first { $0.kind == "faces" }!) }
        var bodies: URL { url(for: manifest.entries.first { $0.kind == "bodies" }!) }
        func discard() { try? FileManager.default.removeItem(at: directory) }
    }
    struct Installed: Sendable { let backup: URL; let musicCount: Int }
    struct Recording: Codable { let file: String; let name: String }
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }

    static func prepare(_ source: URL) throws -> Prepared {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (13...maximumSize).contains(size) else {
            throw Failure.invalid("Choose a Plaza resource pack smaller than 512 MB.")
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try readExactly(input, count: 8) == magic else { throw Failure.invalid("This is not a Plaza resource pack.") }
        let lengthBytes = try readExactly(input, count: 4)
        let length = lengthBytes.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        guard (1...65_536).contains(length) else { throw Failure.invalid("The pack manifest is invalid.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: readExactly(input, count: length))
        try validate(manifest)
        guard manifest.entries.reduce(12 + length, { $0 + $1.size }) == size else {
            throw Failure.invalid("The resource pack is incomplete or has unexpected content.")
        }
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("PlazaResourcePack-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            for entry in manifest.entries {
                let url = directory.appendingPathComponent(entry.file)
                guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw Failure.invalid("Could not stage the pack. Check available disk space.")
                }
                let output = try FileHandle(forWritingTo: url)
                do {
                    var remaining = entry.size, hash = SHA256()
                    while remaining > 0 {
                        let bytes = try readExactly(input, count: min(1_048_576, remaining))
                        try output.write(contentsOf: bytes); hash.update(data: bytes); remaining -= bytes.count
                    }
                    try output.close()
                    guard hex(hash.finalize()) == entry.sha256 else { throw Failure.invalid("A resource failed its checksum. Request a fresh copy of the pack.") }
                } catch { try? output.close(); throw error }
                if entry.kind == "music" { try MusicFileValidation.validate(url) }
            }
            let faces = directory.appendingPathComponent(manifest.entries.first { $0.kind == "faces" }!.file)
            guard try Data(contentsOf: faces, options: .mappedIfSafe).prefix(4) == Data("FFRA".utf8) else {
                throw Failure.invalid("The pack does not contain a valid Wii U face resource.")
            }
            let bodies = directory.appendingPathComponent(manifest.entries.first { $0.kind == "bodies" }!.file)
            let count = try checkBodies(Data(contentsOf: bodies))
            return Prepared(directory: directory, manifest: manifest, animationCount: count)
        } catch { try? fm.removeItem(at: directory); throw error }
    }

    private static func validate(_ manifest: Manifest) throws {
        guard manifest.version == 1, !manifest.name.isEmpty, manifest.name.count <= 100,
              (2...8).contains(manifest.entries.count) else { throw Failure.invalid("This resource pack version is not supported.") }
        var names = Set<String>(), kinds = Set<String>(), music = Set<String>()
        for entry in manifest.entries {
            guard !entry.file.isEmpty, entry.file.count <= 100,
                  entry.file.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
                  !entry.file.contains(".."), names.insert(entry.file).inserted,
                  !entry.name.isEmpty, entry.name.count <= 100, entry.size > 0,
                  entry.sha256.count == 64, entry.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw Failure.invalid("The pack contains invalid file information.")
            }
            switch entry.kind {
            case "faces":
                guard entry.file == "FFLResHigh.dat", entry.role == nil, (1024...64 * 1024 * 1024).contains(entry.size), kinds.insert("faces").inserted else { throw Failure.invalid("Invalid or duplicate face resource.") }
            case "bodies":
                guard entry.file == "plaza-body.json", entry.role == nil, entry.size <= 16 * 1024 * 1024, kinds.insert("bodies").inserted else { throw Failure.invalid("Invalid or duplicate body resource.") }
            case "music":
                guard let role = entry.role, roles.contains(role), music.insert(role).inserted,
                      entry.size <= 256 * 1024 * 1024,
                      ["m4a", "wav", "mp3", "aac", "aif", "aiff", "caf", "flac"].contains(URL(fileURLWithPath: entry.file).pathExtension.lowercased()) else { throw Failure.invalid("Invalid or duplicate music recording.") }
            default: throw Failure.invalid("The pack contains an unsupported resource type.")
            }
        }
        guard kinds == Set(["faces", "bodies"]) else { throw Failure.invalid("The pack must contain both face and body resources.") }
    }

    private static func checkBodies(_ data: Data) throws -> Int {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["version"] as? Int == 1,
              let models = object["models"] as? [[String: Any]], models.count == 2,
              let clips = object["animations"] as? [[String: Any]], (6...256).contains(clips.count),
              let texture = object["texture"] as? [String: Any], texture["data"] is [Int] else {
            throw Failure.invalid("The pack's body and animation data is invalid.")
        }
        return clips.count
    }
    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let bytes = try handle.read(upToCount: count - result.count), !bytes.isEmpty else { throw Failure.invalid("The resource pack is truncated.") }
            result.append(bytes)
        }
        return result
    }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// Only renderer assets, selected music files and their manifest are touched.
    /// All replaced files are backed up before writes; a failed commit rolls back.
    static func install(_ pack: Prepared, at root: URL, checkpoint: ((Int) throws -> Void)? = nil) throws -> Installed {
        let fm = FileManager.default
        for directory in [root, root.appendingPathComponent("Renderer"), root.appendingPathComponent("Music"), root.appendingPathComponent("ResourcePackBackups")] {
            if fm.fileExists(atPath: directory.path) {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.invalid("The plaza data folders must be ordinary folders.") }
            } else { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        }
        struct Write { let path: String; let source: URL?; let data: Data? }
        var writes = [Write(path: "Renderer/FFLResHigh.dat", source: pack.faces, data: nil),
                      Write(path: "Renderer/plaza-body.json", source: pack.bodies, data: nil),
                      Write(path: "Renderer/resource-info.txt", source: nil, data: Data("Installed from a Plaza resource pack.\n".utf8)),
                      Write(path: "Renderer/body-info.txt", source: nil, data: Data("Original Wii U bodies; \(pack.animationCount) animation clips.\n".utf8))]
        if !pack.music.isEmpty {
            let manifest = root.appendingPathComponent("Music/music.json")
            var recordings: [String: Recording] = [:]
            if fm.fileExists(atPath: manifest.path) {
                guard (try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 65_536 else { throw Failure.invalid("The existing music library is too large to update safely.") }
                recordings = try JSONDecoder().decode([String: Recording].self, from: Data(contentsOf: manifest))
            }
            for entry in pack.music {
                let name = UUID().uuidString + "." + URL(fileURLWithPath: entry.file).pathExtension.lowercased()
                recordings[entry.role!] = Recording(file: name, name: entry.name)
                writes.append(Write(path: "Music/" + name, source: pack.url(for: entry), data: nil))
            }
            writes.append(Write(path: "Music/music.json", source: nil, data: try JSONEncoder().encode(recordings)))
        }
        let backup = root.appendingPathComponent("ResourcePackBackups/\(UUID().uuidString)")
        try fm.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var existed = Set<String>()
        // Complete every backup before modifying any destination file.
        for write in writes {
            let destination = root.appendingPathComponent(write.path)
            if fm.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.invalid("An existing resource is not an ordinary file.") }
                let copy = backup.appendingPathComponent(write.path)
                try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: destination, to: copy); existed.insert(write.path)
            }
        }
        let readme = "Previous renderer resources and music manifest. Old music files are retained in Music. To restore, quit Mac Plaza and copy these backed-up files over their matching files in the MacPlaza data folder. Saved characters, notes, apps and accounts are not part of this backup.\n"
        try Data(readme.utf8).write(to: backup.appendingPathComponent("Read Me.txt"))
        var completed: [Write] = []
        do {
            for (index, write) in writes.enumerated() {
                let data = try write.data ?? Data(contentsOf: write.source!, options: .mappedIfSafe)
                try data.write(to: root.appendingPathComponent(write.path), options: .atomic)
                completed.append(write)
                try checkpoint?(index + 1)
            }
        } catch {
            var rollbackFailed = false
            for write in completed.reversed() {
                do {
                    let destination = root.appendingPathComponent(write.path)
                    if existed.contains(write.path) {
                        try Data(contentsOf: backup.appendingPathComponent(write.path), options: .mappedIfSafe).write(to: destination, options: .atomic)
                    } else { try fm.removeItem(at: destination) }
                } catch { rollbackFailed = true }
            }
            if rollbackFailed { throw Failure.invalid("The import failed and a backup needs manual restoration: \(backup.path)") }
            throw error
        }
        return Installed(backup: backup, musicCount: pack.music.count)
    }
}
