import Foundation

enum BugReport {
    static func emailURL(version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") -> URL {
        var url = URLComponents()
        url.scheme = "mailto"; url.path = "alexanderhosier@squidproductions.org"
        url.queryItems = [URLQueryItem(name: "subject", value: "Mac Plaza \(version) bug report"),
            URLQueryItem(name: "body", value: "What happened?\n\nSteps to reproduce:\n1. \n\nWhat did you expect?\n\nMac Plaza version: \(version)\n")]
        return url.url!
    }
}
