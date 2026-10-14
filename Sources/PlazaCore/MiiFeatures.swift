import Foundation

public struct MiiFeatures: Codable, Equatable, Sendable {
    public var eyeColor = 0
    public var eyeSize = 0.5
    public var eyeStretch = 0.5
    public var eyeRotation = 0.5
    public var eyeY = 12.0/18
    public var browColor = 1
    public var browSize = 0.5
    public var browStretch = 0.5
    public var browRotation = 0.5
    public var browSpacing = 2.0/12
    public var browY = 7.0/15
    public var noseSize = 0.5
    public var noseY = 0.5
    public var mouthColor = 0
    public var mouthSize = 0.5
    public var mouthStretch = 0.5
    public var mouthY = 13.0/18
    public var glassesType = 1
    public var glassesColor = 0
    public var glassesSize = 0.5
    public var glassesY = 0.5
    public var mustache = 0
    public var beardType = 1
    public var facialHairColor = 1
    public var mustacheSize = 0.5
    public var mustacheY = 0.5
    public var mole = false
    public var moleSize = 0.5
    public var moleX = 0.65
    public var moleY = 0.65
    public var wrinkles = 0
    public var makeup = 0
    public var flipHair = false
    public var gender = 0
    public var birthMonth = 0
    public var birthDay = 0
    public var favorite = false
    public var creator = ""
    public var allowCopying = true
    public var sharing = true
    public init() {}
    public func validate() throws {
        guard [eyeSize, eyeStretch, eyeRotation, eyeY, browSize, browStretch, browRotation, browSpacing, browY, noseSize, noseY, mouthSize, mouthStretch, mouthY, glassesSize, glassesY, mustacheSize, mustacheY, moleSize, moleX, moleY].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              (0...5).contains(eyeColor), (0...7).contains(browColor), (0...4).contains(mouthColor), (0...8).contains(glassesType), (0...5).contains(glassesColor), (0...5).contains(mustache), (0...5).contains(beardType), (0...7).contains(facialHairColor), (0...11).contains(wrinkles), (0...11).contains(makeup), (0...1).contains(gender), (0...12).contains(birthMonth), (0...31).contains(birthDay), creator.count <= 24
        else { throw PlazaError.invalid("A facial feature or profile setting is invalid.") }
    }
}

public struct LocalReply: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var authorID: UUID
    public var author: String
    public var text: String
    public var created = Date()
    public init(authorID: UUID, author: String, text: String) { self.authorID = authorID; self.author = author; self.text = text }
    public func validate() throws { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 280, author.count <= 24 else { throw PlazaError.invalid("A reply is empty or too long.") } }
}

public struct NoteDraft: Codable, Equatable, Sendable {
    public var text = ""
    public var drawing: [InkStroke] = []
    public var description = ""
    public var appID: UUID?
    public var authorID: UUID?
    public var shared: Bool?
    public var isPublic: Bool { shared ?? true }
    public init() {}
    public var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !drawing.isEmpty ||
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public func validate() throws {
        guard text.count <= 280, description.count <= 160, drawing.count <= 512, drawing.reduce(0, { $0 + $1.points.count }) <= 20000, drawing.allSatisfy({ $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } }) else { throw PlazaError.invalid("The journal draft is invalid.") }
    }
}
