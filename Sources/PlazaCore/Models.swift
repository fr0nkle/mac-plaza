import Foundation

public struct Avatar: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "You"
    public var skin = 0
    public var hair = 33
    public var hairColor = 1
    public var eyes = 2
    public var brows = 0
    public var nose = 1
    public var mouth = 23
    public var glasses = false
    public var beard = false
    public var face = 0
    public var eyeSpacing = 2.0/12
    public var featureHeight = 0.5
    public var height = 0.5
    public var build = 0.5
    public var outfit = 0
    public init(name: String = "You", outfit: Int = 0) { self.name = name; self.outfit = outfit }
    public var features = MiiFeatures()
    public func validated() throws -> Avatar {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 24,
              (0...5).contains(skin), (0...131).contains(hair), (0...7).contains(hairColor),
              (0...59).contains(eyes), (0...23).contains(brows), (0...17).contains(nose),
              (0...35).contains(mouth), (0...11).contains(face), (0...11).contains(outfit),
              [eyeSpacing, featureHeight, height, build].allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else { throw PlazaError.invalid("Character settings are outside the supported range.") }
        try features.validate()
        return self
    }

}

public struct AppIsland: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var label: String
    public var bundleID: String
    public var path: String?
    public var bookmark: Data?
    public var customIcon: Data?
    public var steamAppID: UInt32?
    public init(label: String, bundleID: String, path: String? = nil, bookmark: Data? = nil) {
        self.label = label; self.bundleID = bundleID; self.path = path; self.bookmark = bookmark
    }
}

public struct InkPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}
public struct InkStroke: Codable, Equatable, Sendable {
    public var points: [InkPoint]
    public var eraser: Bool
    public init(points: [InkPoint], eraser: Bool = false) { self.points = points; self.eraser = eraser }
}
public struct LocalNote: Codable, Identifiable, Equatable, Sendable {
    /// Missing on older saves: keep private until the owner chooses to share.
    public var shared: Bool?
    public var id = UUID()
    public var authorID: UUID
    public var author: String
    public var appID: UUID?
    public var text: String
    public var drawing: [InkStroke]
    public var drawingDescription: String
    public var created = Date()
    public var acknowledged = false
    public var replies: [LocalReply]?
    public var read: Bool?
    public init(authorID: UUID, author: String, appID: UUID?, text: String, drawing: [InkStroke] = [], drawingDescription: String = "") {
        self.shared = true
        self.authorID = authorID; self.author = author; self.appID = appID; self.text = text
        self.drawing = drawing; self.drawingDescription = drawingDescription
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public static let defaultPopulation = 160
    public static let populationRange = 20...200
    public var population = Self.defaultPopulation
    public var pauseMotion = false
    public var pausePosts = false
    public var privatePresentation = false
    public var safeMode = false
    public var largerText: Bool?
    public var ambientSound: Bool?
    public var musicVolume: Double?
    public var makerMusicVolume: Double?
    public var friendsMusicVolume: Double?
    public var settingsMusicVolume: Double?
    public var writingMusicVolume: Double?
    public var uiSoundEffects: Bool?
    public var uiSoundVolume: Double?
    public var miiverseMusicVolume: Double?
    public var rotatingHomeScreen: Bool?
    public init() {}
}
public struct PlazaDocument: Codable, Equatable, Sendable {
    public static let maximumCustomMiis = 100
    public var version = 2
    public var apps: [AppIsland] = []
    public var avatars: [Avatar] = [Avatar()]
    public var primaryAvatarID: UUID?
    public var notes: [LocalNote] = []
    public var preferences = Preferences()
    public var draft: NoteDraft?
    public init() { primaryAvatarID = avatars.first?.id }
    public var primaryAvatar: Avatar { avatars.first(where: { $0.id == primaryAvatarID }) ?? avatars[0] }
    public func validated() throws -> PlazaDocument {
        guard version == 2 else { throw PlazaError.invalid("This plaza uses an unsupported file version. Your current plaza was preserved.") }
        guard apps.count <= 120, (1...Self.maximumCustomMiis).contains(avatars.count), notes.count <= 200, notes.reduce(0, { $0 + ($1.replies?.count ?? 0) }) <= 2000,
              Set(apps.map(\.id)).count == apps.count,
              Set(avatars.map(\.id)).count == avatars.count,
              Set(notes.map(\.id)).count == notes.count,
              primaryAvatarID.map({ id in avatars.contains { $0.id == id } }) ?? true,
              Preferences.populationRange.contains(preferences.population),
              preferences.musicVolume.map({ $0.isFinite && (0...0.35).contains($0) }) ?? true,
              preferences.makerMusicVolume.map({ $0.isFinite && (0...0.35).contains($0) }) ?? true,
              preferences.friendsMusicVolume.map({ $0.isFinite && (0...0.35).contains($0) }) ?? true,
              preferences.settingsMusicVolume.map({ $0.isFinite && (0...0.35).contains($0) }) ?? true,
              preferences.writingMusicVolume.map({ $0.isFinite && (0...0.35).contains($0) }) ?? true,
              preferences.uiSoundVolume.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              preferences.miiverseMusicVolume.map({ $0.isFinite && (0...0.35).contains($0) }) ?? true,
              notes.reduce(0, { $0 + $1.drawing.count }) <= 4096,
              notes.reduce(0, { $0 + $1.drawing.reduce(0, { $0 + $1.points.count }) }) + (draft?.drawing.reduce(0, { $0 + $1.points.count }) ?? 0) <= 60000
        else { throw PlazaError.invalid("The plaza contains invalid or excessive records.") }
        for avatar in avatars { _ = try avatar.validated() }
        for app in apps {
            guard !app.label.isEmpty, app.label.count <= 60, app.bundleID.count <= 250,
                  app.steamAppID.map({ $0 > 0 }) ?? true,
                  app.path.map({ $0.hasPrefix("/") && $0.hasSuffix(".app") && $0.count < 4096 }) ?? true,
                  (app.bookmark?.count ?? 0) < 65536, (app.customIcon?.count ?? 0) <= 250_000
            else { throw PlazaError.invalid("An app shortcut is invalid.") }
        }
        guard apps.reduce(0, { $0 + ($1.customIcon?.count ?? 0) }) <= 2_000_000 else { throw PlazaError.invalid("Custom icons exceed the 2 MB plaza budget.") }
        if let draft { try draft.validate() }
        for note in notes {
            guard (note.replies?.count ?? 0) <= 50 else { throw PlazaError.invalid("A note supports up to 50 local replies.") }
            for reply in note.replies ?? [] { try reply.validate() }
            guard note.text.count <= 280, note.author.count <= 24,
                  !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !note.drawing.isEmpty,
                  note.drawing.count <= 512, note.drawing.reduce(0, { $0 + $1.points.count }) <= 20000,
                  note.drawing.isEmpty || (1...160).contains(note.drawingDescription.count),
                  note.drawing.allSatisfy({ $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } })
            else { throw PlazaError.invalid("A note or drawing is invalid or exceeds its limit.") }
        }
        return self
    }
    public func portable() -> PlazaDocument {
        var result = self
        result.apps = apps.map { var app = $0; app.path = nil; app.bookmark = nil; return app }
        return result
    }
}
public enum PlazaError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}

/// Reproducible scene randomness. Simulation never publishes UI state each frame.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    public var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    public mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
}

/// Atomic snapshots with a last-known-good backup. No disk IO on the render thread.
public actor DocumentStorage {
    public nonisolated let url: URL
    private var lastRevision = -1
    public init(url: URL) { self.url = url }
    public func load() throws -> PlazaDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decode(data)
    }
    public static func decode(_ data: Data) throws -> PlazaDocument {
        guard data.count <= 12_000_000 else { throw PlazaError.invalid("Plaza files must be smaller than 12 MB.") }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["version"] as? Int else { throw PlazaError.invalid("This is not a plaza document.") }
        if version == 1 {
            let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MiiFeatures()))
            if let avatars = object["avatars"] as? [[String: Any]] {
                object["avatars"] = avatars.map { avatar in var migrated = avatar; migrated["features"] = defaults; return migrated }
            }
            object["version"] = 2
        }
        return try JSONDecoder().decode(PlazaDocument.self, from: JSONSerialization.data(withJSONObject: object)).validated()
    }
    public func save(_ document: PlazaDocument, revision: Int) throws {
        guard revision > lastRevision else { return }
        _ = try document.validated()
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 12_000_000 else { throw PlazaError.invalid("The saved plaza exceeds 12 MB. Reduce drawings or custom icons.") }
        if let existing = try? Data(contentsOf: url), (try? Self.decode(existing)) != nil {
            try existing.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        lastRevision = revision
    }
    public func beginSession() throws -> Bool {
        let marker=url.appendingPathExtension("session")
        let interrupted=FileManager.default.fileExists(atPath:marker.path)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("running".utf8).write(to:marker,options:.atomic)
        return interrupted
    }
    public func endSession() throws { let marker=url.appendingPathExtension("session"); if FileManager.default.fileExists(atPath:marker.path) { try FileManager.default.removeItem(at:marker) } }
    public func recoverBackup() throws -> PlazaDocument {
        try Self.decode(Data(contentsOf: url.appendingPathExtension("backup")))
    }
}
