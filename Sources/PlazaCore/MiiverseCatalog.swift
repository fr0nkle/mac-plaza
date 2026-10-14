import Foundation

public enum MiiverseSort: String, CaseIterable, Sendable {
    case newest = "Newest", oldest = "Oldest", liked = "Most liked"
}

public struct MiiverseEntry: Identifiable, Sendable {
    public var id: UUID { note.id }
    public let note: LocalNote
    public let sectionID: String
    public let sectionLabel: String
    public let own: Bool
    public let likeCount: Int
    public let displayName: String
}

public struct MiiverseSection: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let count: Int
    public let appID: UUID?
}

/// A read-only index; portable topic identity groups notes without requiring a local shortcut.
public struct MiiverseCatalog: Sendable {
    public let entries: [MiiverseEntry]
    public let sections: [MiiverseSection]
    public static func topicID(_ topic: SharedNoteTopic) -> String {
        topic.steamAppID.map { "steam:\($0)" } ?? "bundle:" + topic.bundleID
    }

    public init(notes: [LocalNote], apps: [AppIsland], shared: [SharedJournalNote], accountID: String?, accountDisplayName: String? = nil) {
        var communities: [String: (label: String, appID: UUID?)] = [:]
        for app in apps {
            let key = Self.topicID(SharedNoteTopic(app))
            if communities[key] == nil { communities[key] = (app.label, app.id) }
        }
        var ownThreads: [UUID: SharedJournalNote] = [:]
        for thread in shared where accountID != nil && thread.ownerID == accountID {
            if let id = thread.sourceID { ownThreads[id] = thread }
        }
        var result: [MiiverseEntry] = []
        var seen = Set<UUID>()
        func append(_ note: LocalNote, topic: SharedNoteTopic?, own: Bool, likes: Int, displayName: String) {
            guard seen.insert(note.id).inserted else { return }
            let key: String
            let label: String
            if let topic {
                key = Self.topicID(topic); label = communities[key]?.label ?? topic.label
            } else if let id = note.appID {
                key = "local:" + id.uuidString; label = "Removed app"
            } else { key = "plaza"; label = "The Plaza" }
            if key != "plaza", communities[key] == nil { communities[key] = (label, nil) }
            result.append(MiiverseEntry(note: note, sectionID: key, sectionLabel: label, own: own, likeCount: likes, displayName: displayName))
        }
        for note in notes {
            let thread = ownThreads[note.id]
            let topic = note.appID.flatMap { id in apps.first { $0.id == id }.map(SharedNoteTopic.init) } ?? thread?.topic
            append(note, topic: topic, own: true, likes: thread?.likeCount ?? 0,
                displayName: note.shared == true ? thread?.publicDisplayName ?? accountDisplayName ?? note.author : note.author)
        }
        let localIDs = Set(notes.map(\.id))
        for thread in shared {
            let own = accountID != nil && thread.ownerID == accountID
            if own && (thread.sourceID.map { localIDs.contains($0) } ?? localIDs.contains(thread.id)) { continue }
            append(thread.localNote(apps: apps), topic: thread.topic, own: own, likes: thread.likeCount ?? 0, displayName: thread.publicDisplayName)
        }
        entries = result
        let counts = Dictionary(grouping: result, by: \.sectionID).mapValues(\.count)
        sections = [
            MiiverseSection(id: "all", label: "All Notes", count: result.count, appID: nil),
            MiiverseSection(id: "mine", label: "My Notes", count: result.filter(\.own).count, appID: nil),
            MiiverseSection(id: "friends", label: "Friends’ Notes", count: result.filter { !$0.own }.count, appID: nil),
            MiiverseSection(id: "plaza", label: "The Plaza", count: counts["plaza"] ?? 0, appID: nil)
        ] + communities.map { key, value in
            MiiverseSection(id: key, label: value.label, count: counts[key] ?? 0, appID: value.appID)
        }.sorted { lhs, rhs in
            let comparison = lhs.label.localizedStandardCompare(rhs.label)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }

    public func filtered(section: String, query: String, sort: MiiverseSort) -> [MiiverseEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let inSection = section == "all" || (section == "mine" && entry.own) ||
                (section == "friends" && !entry.own) || section == entry.sectionID
            return inSection && (query.isEmpty || [entry.note.text, entry.displayName,
                entry.note.drawingDescription, entry.sectionLabel].contains { $0.localizedCaseInsensitiveContains(query) })
        }.sorted { lhs, rhs in
            if sort == .liked && lhs.likeCount != rhs.likeCount { return lhs.likeCount > rhs.likeCount }
            if lhs.note.created != rhs.note.created {
                return sort == .oldest ? lhs.note.created < rhs.note.created : lhs.note.created > rhs.note.created
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
