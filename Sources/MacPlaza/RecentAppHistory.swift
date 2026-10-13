import Foundation
import PlazaCore
import CryptoKit

/// Local usage history is intentionally separate from shareable plaza exports.
final class RecentAppHistory {
    struct Entry: Codable { var app: AppIsland; var launched: Date }
    private struct Saved: Codable { var entries: [Entry]; var previous: [String] }
    private(set) var entries: [Entry] = []
    private(set) var previous: [String] = []
    let url: URL

    init(url: URL, now: Date = Date()) {
        self.url = url
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_000_000,
              let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        var seen = Set<String>()
        entries = Array(saved.entries.filter {
            $0.launched.timeIntervalSince1970.isFinite && $0.launched <= now.addingTimeInterval(60) &&
            now.timeIntervalSince($0.launched) < 90 * 86400 &&
            !$0.app.bundleID.isEmpty && $0.app.bundleID.count <= 250 &&
            $0.app.path.map { $0.hasPrefix("/") && $0.hasSuffix(".app") && $0.count < 4096 } == true &&
            seen.insert(HomeScreenRotation.key($0.app)).inserted
        }.sorted { $0.launched > $1.launched }.prefix(60))
        previous = Array(saved.previous.filter { $0.count <= 300 }.prefix(12))
    }

    static func stableID(for app: AppIsland) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(HomeScreenRotation.key(app).utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func record(_ app: AppIsland, at date: Date = Date()) throws {
        var copy = app
        copy.id = Self.stableID(for: app)
        copy.customIcon = nil
        let key = HomeScreenRotation.key(app)
        if let entry = entries.first(where: { HomeScreenRotation.key($0.app) == key }), entry.launched >= date { return }
        entries.removeAll { HomeScreenRotation.key($0.app) == key }
        entries.insert(Entry(app: copy, launched: date), at: 0)
        entries = Array(entries.sorted { $0.launched > $1.launched }.prefix(60))
        try save()
    }

    func remember(_ apps: [AppIsland]) throws {
        previous = apps.map(HomeScreenRotation.key)
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Saved(entries: entries, previous: previous)).write(to: url, options: .atomic)
    }
}

enum InstalledHomeApps {
    /// Stop at packages, skip hidden helpers, and bound vendor subfolder traversal.
    static func applicationURLs(roots: [URL] = [URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]) -> [URL] {
        var pending = roots.map { ($0, 0) }, result: [URL] = [], examined = 0
        while !pending.isEmpty && examined < 4096 {
            let (folder, depth) = pending.removeFirst()
            let children = (try? FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
            for child in children {
                examined += 1
                guard examined <= 4096,
                      let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                if child.pathExtension.lowercased() == "app" { result.append(child) }
                else if depth < 2 { pending.append((child, depth + 1)) }
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}
