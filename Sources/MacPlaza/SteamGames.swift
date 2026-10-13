import Foundation

/// Read Steam's local library manifests; no account access or network requests.
enum SteamGames {
    struct Game: Identifiable, Equatable, Sendable {
        let id: UInt32
        let name: String
        let applicationURL: URL
        var launchURL: URL { URL(string: "steam://rungameid/\(id)")! }
    }

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
    }

    static func installed(root: URL = defaultRoot) -> [Game] {
        var libraries = [root.standardizedFileURL]
        if let folders = read(root.appendingPathComponent("steamapps/libraryfolders.vdf"))?["libraryfolders"]?.object {
            for (key, value) in folders where UInt(key) != nil {
                if let path = value.object?["path"]?.string ?? value.string, path.hasPrefix("/") {
                    libraries.append(URL(fileURLWithPath: path).standardizedFileURL)
                }
            }
        }
        var games: [UInt32: Game] = [:]
        for library in Set(libraries) {
            let apps = library.appendingPathComponent("steamapps")
            let manifests = (try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []
            for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                guard let state = read(manifest)?["AppState"]?.object,
                      let game = game(state: state, steamapps: apps, manifest: manifest), games[game.id] == nil else { continue }
                games[game.id] = game
            }
        }
        return games.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A selected .app can also acquire its Steam identity without a library scan.
    static func game(forApplication url: URL) -> Game? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app" else { return nil }
        var parent = url.deletingLastPathComponent()
        for _ in 0..<6 {
            if parent.lastPathComponent == "common", parent.deletingLastPathComponent().lastPathComponent == "steamapps" {
                let apps = parent.deletingLastPathComponent()
                let manifests = (try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil)) ?? []
                for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                    guard let state = read(manifest)?["AppState"]?.object,
                          let game = game(state: state, steamapps: apps, manifest: manifest),
                          game.applicationURL.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() else { continue }
                    return game
                }
                return nil
            }
            let next = parent.deletingLastPathComponent()
            if next == parent { break }
            parent = next
        }
        return nil
    }

    private static func game(state: [String: Value], steamapps: URL, manifest: URL) -> Game? {
        guard let rawID = state["appid"]?.string, let id = UInt32(rawID), id > 0,
              manifest.lastPathComponent == "appmanifest_\(id).acf",
              let name = state["name"]?.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let directory = state["installdir"]?.string, !directory.isEmpty,
              directory != ".", directory != "..", !directory.contains("/"), !directory.contains("\\"),
              let flags = state["StateFlags"]?.string.flatMap(UInt.init), flags & 4 != 0 else { return nil }
        let folder = steamapps.appendingPathComponent("common").appendingPathComponent(directory)
        guard let application = application(in: folder, name: name) else { return nil }
        return Game(id: id, name: String(name.prefix(60)), applicationURL: application)
    }

    private static func application(in folder: URL, name: String) -> URL? {
        // Stop at app packages: launchers/helper apps inside Contents are not games.
        var pending: [(URL, Int)] = [(folder, 0)]
        var examined = 0
        while !pending.isEmpty, examined < 512 {
            let (directory, depth) = pending.removeFirst()
            let children = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? [])
                .sorted {
                    func preferred(_ url: URL) -> Bool {
                        let title = url.deletingPathExtension().lastPathComponent
                        return title.caseInsensitiveCompare(name) == .orderedSame || title.caseInsensitiveCompare(folder.lastPathComponent) == .orderedSame
                    }
                    if preferred($0) != preferred($1) { return preferred($0) }
                    return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
            for child in children {
                examined += 1
                guard examined <= 512, let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                if child.pathExtension.lowercased() == "app" {
                    if let bundle = Bundle(url: child), bundle.bundleIdentifier != nil,
                       let executable = bundle.executableURL, FileManager.default.fileExists(atPath: executable.path) { return child }
                } else if depth < 3 { pending.append((child, depth + 1)) }
            }
        }
        return nil
    }

    private static func read(_ url: URL) -> [String: Value]? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
              let data = try? Data(contentsOf: url), data.count <= 2_000_000,
              let source = String(data: data, encoding: .utf8) else { return nil }
        var parser = KeyValues(source: Array(source))
        return parser.object(depth: 0, nested: false)
    }

    private indirect enum Value {
        case text(String), dictionary([String: Value])
        var string: String? { if case .text(let value) = self { return value }; return nil }
        var object: [String: Value]? { if case .dictionary(let value) = self { return value }; return nil }
    }

    /// Small bounded KeyValues reader, including quoted escapes and // comments.
    private struct KeyValues {
        let source: [Character]
        var index = 0
        mutating func token() -> String? {
            while index < source.count {
                if source[index].isWhitespace { index += 1; continue }
                if source[index] == "/", index + 1 < source.count, source[index + 1] == "/" {
                    while index < source.count, source[index] != "\n" { index += 1 }; continue
                }
                break
            }
            guard index < source.count else { return nil }
            let first = source[index]; index += 1
            if first == "{" || first == "}" { return String(first) }
            var result = ""
            if first == "\"" {
                while index < source.count {
                    let character = source[index]; index += 1
                    if character == "\"" { return result }
                    if character == "\\", index < source.count {
                        let escaped = source[index]; index += 1
                        switch escaped { case "n": result.append("\n"); case "t": result.append("\t"); default: result.append(escaped) }
                    } else { result.append(character) }
                }
                return nil
            }
            result.append(first)
            while index < source.count, !source[index].isWhitespace, source[index] != "{", source[index] != "}" {
                result.append(source[index]); index += 1
            }
            return result
        }
        mutating func object(depth: Int, nested: Bool) -> [String: Value]? {
            guard depth <= 16 else { return nil }
            var result: [String: Value] = [:]
            while let key = token() {
                if key == "}" { return nested ? result : nil }
                guard key != "{", let value = token(), value != "}" else { return nil }
                if value == "{" {
                    guard let child = object(depth: depth + 1, nested: true) else { return nil }
                    result[key] = .dictionary(child)
                } else { result[key] = .text(value) }
            }
            return nested ? nil : result
        }
    }
}
