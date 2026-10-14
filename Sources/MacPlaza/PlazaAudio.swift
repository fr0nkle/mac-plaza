import AppKit
import AVFoundation
import PlazaCore
import OSLog

/// Local soundtrack playback; no network or web player is needed at runtime.
@MainActor
final class PlazaAudio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let resourceRoots: [URL]
    init(resourceRoots: [URL] = PlazaResources.searchRoots) {
        self.resourceRoots = resourceRoots
        super.init()
    }
    private func recordingURL(for track: Track) -> URL? {
        PlazaResources.url(for: track.rawValue, extension: "m4a", directory: "Audio", roots: resourceRoots)
    }
    enum Track: String { case plaza = "warawara-home", maker = "mii-maker", friends = "friends-menu", settings = "system-settings", writing = "note-writing", miiverse = "miiverse" }
    static let crossfadeDuration: TimeInterval = 1.2
    private final class Voice {
        let player: AVAudioPlayer
        let track: Track
        let source: URL?
        var targetVolume: Float = 0
        var retirement: Task<Void, Never>?
        init(player: AVAudioPlayer, track: Track, source: URL?) {
            self.player = player; self.track = track; self.source = source
        }
        deinit { retirement?.cancel() }
    }
    private var voice: Voice?
    private var fadingVoices: [Voice] = []
    // A menu may remain open long after the outgoing player is released.
    // Retain the plaza playhead, scoped to the selected recording, for this session.
    private var plazaPlayhead: (source: URL?, time: TimeInterval)?
    private var interruptedPlayhead: (track: Track, source: URL?, time: TimeInterval)?
    private let logger = Logger(subsystem: "local.macplaza.audio", category: "Playback")
    private var playbackRetry: Task<Void, Never>?
    private var playbackRetries = 0
    private var previewPlayer: AVAudioPlayer?
    private var effects:[(cue:PlazaArrival.Cue,player:AVAudioPlayer)]=[]
    var effectPlayback:[(cue:PlazaArrival.Cue,playing:Bool,volume:Float)] {
        effects.map {($0.cue,$0.player.isPlaying,$0.player.volume)}
    }
    static func arrivalEffectURL(for cue:PlazaArrival.Cue)->URL? {
        PlazaResources.url(for: cue.rawValue, extension: "wav", directory: "Audio")
    }
    func playArrivalEffect(_ cue:PlazaArrival.Cue,volume:Double) {
        guard backgroundRequest?.enabled == true,previewPlayer == nil,volume.isFinite,volume>0,
              let url=PlazaResources.url(for:cue.rawValue,extension:"wav",directory:"Audio",roots:resourceRoots),let player=try? AVAudioPlayer(contentsOf:url) else{return}
        effects.removeAll {if !$0.player.isPlaying {$0.player.stop();return true};return false}
        player.numberOfLoops=0;player.volume=Float(min(0.35,max(0,volume*1.4)));player.delegate=self
        guard player.prepareToPlay(),player.play() else{return}
        effects.append((cue,player))
    }
    func stopArrivalEffects() {
        effects.forEach {$0.player.stop()};effects=[]
    }
    @Published private(set) var previewTrack: Track?
    private(set) var previewURL: URL?
    private var backgroundRequest: (enabled: Bool, volume: Double, track: Track, url: URL?)?
    var isBackgroundPlaying: Bool { voice?.player.isPlaying == true }
    // Read-only playback state also lets regression checks inspect both sides
    // of a real crossfade, including rapid changes and preview interruption.
    var backgroundPlayback: [(track: Track, source: URL?, playing: Bool, volume: Float, time: TimeInterval)] {
        ([voice].compactMap { $0 } + fadingVoices).map {
            ($0.track, $0.source, $0.player.isPlaying, $0.player.volume, $0.player.currentTime)
        }
    }
    static var soundtrackURL: URL? { soundtrackURL(for: .plaza) }
    static func soundtrackURL(for track: Track) -> URL? {
        PlazaResources.url(for: track.rawValue, extension: "m4a", directory: "Audio")
    }
    func update(enabled: Bool, volume: Double = 0.12, track: Track = .plaza, customURL: URL? = nil, allowPreview: Bool = true) {
        backgroundRequest = (enabled, volume, track, customURL)
        if !allowPreview { clearPreview() }
        if previewPlayer != nil || !enabled {
            playbackRetry?.cancel(); playbackRetry = nil; playbackRetries = 0
            stopArrivalEffects(); pauseBackground(); return
        }
        let level = Float(volume.isFinite ? max(0, min(0.35, volume)) : 0.12)
        effects.forEach {$0.player.setVolume(min(0.35,level*1.4),fadeDuration:0.06)}
        let source = customURL ?? recordingURL(for: track)
        if voice?.track != track || voice?.source != source {
            let next: Voice
            if let index = fadingVoices.firstIndex(where: { $0.track == track && $0.source == source }) {
                // Reversing direction mid-fade reuses the still-playing track.
                next = fadingVoices.remove(at: index)
                next.retirement?.cancel(); next.retirement = nil
            } else {
                var player = source.flatMap { try? AVAudioPlayer(contentsOf: $0) }
                if player == nil, customURL != nil { player = recordingURL(for: track).flatMap { try? AVAudioPlayer(contentsOf: $0) } }
                if player == nil { player = try? AVAudioPlayer(data: Self.loop()) }
                guard let player else { return }
                player.numberOfLoops = -1
                player.volume = 0
                if track == .plaza, let saved = plazaPlayhead, saved.source == source,
                   saved.time.isFinite, saved.time >= 0, player.duration.isFinite, player.duration > 0 {
                    player.currentTime = saved.time.truncatingRemainder(dividingBy: player.duration)
                } else if let saved = interruptedPlayhead, saved.track == track, saved.source == source,
                          saved.time.isFinite, saved.time >= 0, player.duration.isFinite, player.duration > 0 {
                    player.currentTime = saved.time.truncatingRemainder(dividingBy: player.duration)
                }
                guard player.prepareToPlay(), player.play() else {
                    logger.error("Playback could not start for role \(track.rawValue, privacy: .public)")
                    pauseBackground()
                    schedulePlaybackRetry()
                    return
                }
                interruptedPlayhead = nil
                next = Voice(player: player, track: track, source: source)
            }
            if let previous = voice { retire(previous) }
            voice = next
            next.targetVolume = level
            next.player.setVolume(level, fadeDuration: Self.crossfadeDuration)
        } else if let voice {
            if !voice.player.isPlaying {
                voice.player.volume = 0
                guard voice.player.play() else {
                    logger.error("Playback could not resume for role \(track.rawValue, privacy: .public)")
                    interruptedPlayhead = (voice.track, voice.source, voice.player.currentTime)
                    release(voice); self.voice = nil
                    schedulePlaybackRetry()
                    return
                }
                voice.targetVolume = level
                voice.player.setVolume(level, fadeDuration: Self.crossfadeDuration)
            } else if voice.targetVolume != level {
                voice.targetVolume = level
                voice.player.setVolume(level, fadeDuration: 0.2)
            }
            // Duplicate view/lifecycle updates must not shorten a crossfade.
        }
        playbackRetry?.cancel(); playbackRetry = nil; playbackRetries = 0
    }
    private func schedulePlaybackRetry() {
        guard playbackRetry == nil, playbackRetries < 3 else { return }
        playbackRetries += 1
        playbackRetry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            guard let self else { return }
            self.playbackRetry = nil
            guard let request = self.backgroundRequest, request.enabled, self.previewPlayer == nil else { return }
            self.update(enabled: request.enabled, volume: request.volume, track: request.track, customURL: request.url)
        }
    }
    private func retire(_ previous: Voice) {
        guard previous.player.isPlaying else { release(previous); return }
        previous.player.setVolume(0, fadeDuration: Self.crossfadeDuration)
        fadingVoices.append(previous)
        previous.retirement = Task { @MainActor [weak self, weak previous] in
            do { try await Task.sleep(for: .seconds(Self.crossfadeDuration)) } catch { return }
            guard let self, let previous else { return }
            self.release(previous)
            self.fadingVoices.removeAll { $0 === previous }
            previous.retirement = nil
        }
    }
    private func release(_ previous: Voice) {
        if previous.track == .plaza {
            plazaPlayhead = (previous.source, previous.player.currentTime)
        }
        previous.player.stop()
    }
    private func pauseBackground() {
        voice?.player.pause()
        for previous in fadingVoices { previous.retirement?.cancel(); release(previous) }
        fadingVoices.removeAll()
    }

    /// Calls can switch Bluetooth/USB routes. Release the old audio queues while
    /// suppressed so returning to music creates a fresh player on the current route.
    func releaseForAudioInterruption() {
        playbackRetry?.cancel(); playbackRetry = nil; playbackRetries = 0
        logger.notice("Releasing playback hardware for other-app audio activity")
        clearPreview()
        stopArrivalEffects()
        if let voice {
            interruptedPlayhead = (voice.track, voice.source, voice.player.currentTime)
            release(voice)
        }
        for previous in fadingVoices {
            previous.retirement?.cancel(); previous.retirement = nil
            release(previous)
        }
        voice = nil
        fadingVoices.removeAll()
    }
    func preview(_ url: URL, track: Track, volume: Double) throws {
        let candidate = try AVAudioPlayer(contentsOf: url)
        guard candidate.duration.isFinite, candidate.duration > 0, candidate.prepareToPlay() else {
            throw FFLError.message("This file contains no playable audio.")
        }
        clearPreview()
        stopArrivalEffects()
        pauseBackground()
        candidate.numberOfLoops = 0
        candidate.volume = 0
        candidate.delegate = self
        guard candidate.play() else {
            resumeBackground()
            throw FFLError.message("The audio preview could not start.")
        }
        previewPlayer = candidate
        previewURL = url
        previewTrack = track
        setPreviewVolume(volume)
    }
    func setPreviewVolume(_ volume: Double) {
        previewPlayer?.setVolume(Float(volume.isFinite ? max(0,min(0.35,volume)) : 0.12), fadeDuration: 0.2)
    }
    func stopPreview() {
        guard previewPlayer != nil else { return }
        clearPreview()
        resumeBackground()
    }
    private func clearPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewURL = nil
        previewTrack = nil
    }
    private func resumeBackground() {
        if let request = backgroundRequest {
            update(enabled: request.enabled, volume: request.volume, track: request.track, customURL: request.url)
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else{return}
            self.effects.removeAll {$0.player === player}
            if self.previewPlayer === player {self.stopPreview()}
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
    // Resource-free fallback retained for development and recovery.
    static func loop() -> Data {
        let sampleRate=22050, beats=32, duration=Double(beats)*0.5, samples=Int(duration*Double(sampleRate))
        let melody=[72,76,79,76,74,77,81,77,71,74,79,74,69,72,76,72,72,76,79,83,81,79,77,74,76,74,72,69,67,71,74,79]
        var pcm=Data(capacity:samples*2)
        for i in 0..<samples {
            let t=Double(i)/Double(sampleRate), beat=min(beats-1,Int(t/0.5)), age=t-Double(beat)*0.5
            let frequency=440*pow(2,Double(melody[beat]-69)/12)
            let envelope=min(1,age/0.012)*exp(-age*7)*min(1,(duration-t)/0.1)
            let wave=(sin(t*frequency*2 * .pi)+0.2*sin(t*frequency*4 * .pi))*envelope*0.18
            var sample=Int16(max(-1,min(1,wave))*32767).littleEndian; withUnsafeBytes(of:&sample) { pcm.append(contentsOf:$0) }
        }
        var data=Data("RIFF".utf8)
        func word(_ n:UInt32) { var n=n.littleEndian; withUnsafeBytes(of:&n) { data.append(contentsOf:$0) } }
        func short(_ n:UInt16) { var n=n.littleEndian; withUnsafeBytes(of:&n) { data.append(contentsOf:$0) } }
        word(UInt32(pcm.count+36)); data.append(Data("WAVEfmt ".utf8)); word(16); short(1); short(1); word(UInt32(sampleRate)); word(UInt32(sampleRate*2)); short(2); short(16); data.append(Data("data".utf8)); word(UInt32(pcm.count)); data.append(pcm); return data
    }
}
