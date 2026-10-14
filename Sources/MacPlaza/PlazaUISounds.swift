import AVFoundation
import SwiftUI

/// Short UI one-shots have their own players, volume and mute state. They never
/// change music playback, previews, fades or the system audio session.
@MainActor
final class PlazaUISounds: NSObject {
    enum Cue: String, CaseIterable { case click, back }
    static let shared = PlazaUISounds()
    private let roots: [URL]
    private var players: [Cue: [AVAudioPlayer]] = [:]
    private var enabled = true
    private var volume: Float = 0.18
    private(set) var playedCount = 0
    private(set) var lastCue: Cue?

    init(roots: [URL] = PlazaResources.searchRoots) { self.roots = roots; super.init() }
    static func recordingURL(_ cue: Cue, roots: [URL] = PlazaResources.searchRoots) -> URL? {
        PlazaResources.url(for: cue.rawValue, extension: "wav", directory: "Audio/UI", roots: roots)
    }
    var playback: [(cue: Cue, playing: Bool, volume: Float)] {
        Cue.allCases.flatMap { cue in (players[cue] ?? []).map { (cue, $0.isPlaying, $0.volume) } }
    }
    func configure(enabled: Bool, volume: Double) {
        self.enabled = enabled
        self.volume = Float(volume.isFinite ? min(1, max(0, volume)) : 0.18)
        for player in players.values.flatMap({ $0 }) {
            player.volume = self.volume
            if !enabled || self.volume == 0 { player.stop() }
        }
    }
    func play(_ cue: Cue) {
        guard enabled, volume > 0 else { return }
        var pool = players[cue] ?? []
        let player: AVAudioPlayer
        if let idle = pool.first(where: { !$0.isPlaying }) { player = idle }
        else if pool.count < 3 {
            guard let url = Self.recordingURL(cue, roots: roots), let next = try? AVAudioPlayer(contentsOf: url) else { return }
            next.numberOfLoops = 0
            guard next.prepareToPlay() else { return }
            pool.append(next); player = next
        } else {
            // Bound rapid-click overlap. Reusing a voice affects only
            // this effect; music is owned by a different object and player.
            player = pool.removeFirst(); player.stop(); pool.append(player)
        }
        player.currentTime = 0; player.volume = volume
        players[cue] = pool
        if player.play() { playedCount += 1; lastCue = cue }
    }
    func stop() { players.values.flatMap { $0 }.forEach { $0.stop() } }
    static func cue(for title: String) -> Cue {
        let text = title.lowercased()
        return text.hasPrefix("back") || text.hasPrefix("cancel") || text.hasPrefix("close") ||
            text.hasPrefix("return to desktop") || text == "categories" || text == "done" ||
            text == "keep draft & close" ? .back : .click
    }
}

/// Keep SwiftUI's button semantics, styles, disabled state, keyboard shortcuts
/// and accessibility activation. Feedback fires only when the action fires.
@MainActor
struct PlazaButton<Label: View>: View {
    let role: ButtonRole?
    let sound: PlazaUISounds.Cue
    let action: () -> Void
    let label: Label
    init(role: ButtonRole? = nil, sound: PlazaUISounds.Cue = .click,
         action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = role; self.sound = sound; self.action = action; self.label = label()
    }
    init(_ title: String, role: ButtonRole? = nil, sound: PlazaUISounds.Cue? = nil,
         action: @escaping () -> Void) where Label == Text {
        self.role = role; self.sound = sound ?? PlazaUISounds.cue(for: title)
        self.action = action; self.label = Text(title)
    }
    var body: some View {
        SwiftUI.Button(role: role) { PlazaUISounds.shared.play(sound); action() } label: { label }
    }
}
