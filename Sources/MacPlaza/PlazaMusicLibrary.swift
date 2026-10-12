import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Managed local copies, deliberately separate from portable plaza exports.
@MainActor
final class PlazaMusicLibrary: ObservableObject {
    struct Recording: Codable {
        let file: String
        let name: String
    }
    struct Selection {
        let url: URL
        let name: String
    }
    @Published private(set) var recordings: [String: Recording] = [:]
    @Published private(set) var selections: [String: Selection] = [:]
    @Published private(set) var message: String?
    @Published private(set) var revision = UUID()
    var onChange: (() -> Void)?
    let directory: URL
    private var manifest: URL { directory.appendingPathComponent("music.json") }
    private var previewDirectory: URL { directory.appendingPathComponent(".preview", isDirectory: true) }
    static let maximumFileSize = 256 * 1024 * 1024

    init(directory: URL) {
        self.directory = directory
        // Unapplied choices from an interrupted session are disposable.
        try? FileManager.default.removeItem(at: previewDirectory)
        if let data = try? Data(contentsOf: manifest),
           let saved = try? JSONDecoder().decode([String: Recording].self, from: data) {
            recordings = saved.filter { key, recording in
                PlazaAudio.Track(rawValue: key) != nil && Self.validFileName(recording.file)
            }
        }
    }
    private static func validFileName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && UUID(uuidString: String(parts[0])) != nil &&
            !parts[1].isEmpty && parts[1].count <= 10 && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    func url(for track: PlazaAudio.Track) -> URL? {
        guard let recording = recordings[track.rawValue] else { return nil }
        let url = directory.appendingPathComponent(recording.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func title(for track: PlazaAudio.Track) -> String {
        if url(for: track) != nil { return recordings[track.rawValue]!.name }
        return track == .plaza ? "WaraWara Plaza · Home" : "Mii Maker"
    }
    func choose(for track: PlazaAudio.Track) {
        let panel = NSOpenPanel()
        panel.title = track == .plaza ? "Choose Plaza Music" : "Choose Mii Maker Music"
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        do { try stage(selected, for: track); message = nil }
        catch { message = "Music was not selected: \(error.localizedDescription)" }
    }
    func stage(_ source: URL, for track: PlazaAudio.Track) throws {
        let recording = try validatedCopy(source, into: previewDirectory)
        discardSelection(for: track)
        selections[track.rawValue] = Selection(url: previewDirectory.appendingPathComponent(recording.file), name: recording.name)
    }
    func previewURL(for track: PlazaAudio.Track) -> URL? {
        selections[track.rawValue]?.url ?? url(for: track) ?? PlazaAudio.soundtrackURL(for: track)
    }
    func applySelection(for track: PlazaAudio.Track) {
        guard let selection = selections[track.rawValue] else { return }
        do {
            try install(selection.url, for: track, displayName: selection.name)
            discardSelection(for: track)
            message = "\(selection.name) applied. It will loop at your chosen volume."
        } catch { message = "Music was not applied: \(error.localizedDescription)" }
    }
    func discardSelection(for track: PlazaAudio.Track) {
        if let selection = selections.removeValue(forKey: track.rawValue) { try? FileManager.default.removeItem(at: selection.url) }
    }
    func discardSelections() {
        discardSelection(for: .plaza)
        discardSelection(for: .maker)
        try? FileManager.default.removeItem(at: previewDirectory)
    }
    private func validatedCopy(_ source: URL, into destination: URL, displayName: String? = nil) throws -> Recording {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0,
              size <= Self.maximumFileSize else {
            throw FFLError.message("Choose an audio file between 1 byte and 256 MB.")
        }
        let ext = source.pathExtension.lowercased()
        let name = UUID().uuidString + "." + (ext.isEmpty ? "audio" : ext)
        guard Self.validFileName(name) else { throw FFLError.message("This audio filename extension is not supported.") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let copy = destination.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: copy)
        do {
            let player = try AVAudioPlayer(contentsOf: copy)
            guard player.duration.isFinite, player.duration > 0, player.prepareToPlay() else {
                throw FFLError.message("The file contains no playable audio.")
            }
            return Recording(file: name, name: displayName ?? source.lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }
    func install(_ source: URL, for track: PlazaAudio.Track, displayName: String? = nil) throws {
        let recording = try validatedCopy(source, into: directory, displayName: displayName)
        let copy = directory.appendingPathComponent(recording.file)
        do {
            var next = recordings
            let previous = next[track.rawValue]
            next[track.rawValue] = recording
            try JSONEncoder().encode(next).write(to: manifest, options: .atomic)
            recordings = next
            revision = UUID()
            onChange?()
            if let previous { try? FileManager.default.removeItem(at: directory.appendingPathComponent(previous.file)) }
        } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
    }
    func restoreDefault(for track: PlazaAudio.Track) {
        do {
            var next = recordings
            let previous = next.removeValue(forKey: track.rawValue)
            try JSONEncoder().encode(next).write(to: manifest, options: .atomic)
            recordings = next
            revision = UUID()
            onChange?()
            if let previous { try? FileManager.default.removeItem(at: directory.appendingPathComponent(previous.file)) }
            message = "Default \(track == .plaza ? "plaza" : "Mii Maker") music restored."
        } catch { message = "Could not restore the default music: \(error.localizedDescription)" }
    }
}
