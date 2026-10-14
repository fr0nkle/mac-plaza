import Foundation

/// Posted notes expire seven 24-hour days after creation. Drafts have no expiry.
public enum NoteRetention {
    public static let duration: TimeInterval = 7 * 24 * 60 * 60
    public static let disclaimer = "Notes and Miiverse posts are automatically deleted 7 days after posting, along with their replies and likes. Editing doesn’t extend this period. Drafts are kept."

    public static func isExpired(_ created: Date, now: Date = Date()) -> Bool {
        created <= now.addingTimeInterval(-duration)
    }
    @discardableResult
    public static func prune(_ document: inout PlazaDocument, now: Date = Date()) -> Int {
        let count = document.notes.count
        document.notes.removeAll { isExpired($0.created, now: now) }
        return count - document.notes.count
    }
}
