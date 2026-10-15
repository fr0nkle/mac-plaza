import Foundation
import Sparkle

/// Receives only Sparkle's selected compatible update. No extra feed fetch,
/// download, persisted announcement, or change to update preferences.
struct PlazaUpdateAvailability: Equatable {
    private(set) var version: String?
    private(set) var displayVersion: String?
    var available: Bool { version != nil }
    mutating func found(version: String, displayVersion: String, installedVersion: String, downloadURL: URL?, source: URL?) {
        clear()
        guard !version.isEmpty, !installedVersion.isEmpty,
              SUStandardVersionComparator.default.compareVersion(installedVersion, toVersion: version) == .orderedAscending,
              let source, let downloadURL,
              ["https", "http"].contains(source.scheme ?? ""), source.host != nil,
              downloadURL.scheme == source.scheme, downloadURL.host == source.host, downloadURL.port == source.port,
              downloadURL.path.hasPrefix("/updates/"), downloadURL.lastPathComponent != "appcast.xml" else { return }
        self.version = version
        self.displayVersion = displayVersion.isEmpty ? version : displayVersion
    }
    mutating func clear() { version = nil; displayVersion = nil }
}
