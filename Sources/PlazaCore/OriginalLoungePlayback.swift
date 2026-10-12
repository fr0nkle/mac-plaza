import Foundation

/// The local resource provides clip headers; executable-derived logic supplies
/// selection and timing. Indices preserve the resource's order for the renderer.
public struct OriginalLoungeCatalog: Sendable {
    public struct Clip: Equatable, Sendable {
        public let name: String
        public let frames: Float
        public let loop: Bool
        public init(name: String, frames: Float, loop: Bool) {
            self.name = name; self.frames = frames; self.loop = loop
        }
    }
    public let clips: [Clip]
    private let lookup: [String: Int]
    public init?(clips: [Clip]) {
        guard (1...256).contains(clips.count), Set(clips.map(\.name)).count == clips.count,
              clips.allSatisfy({ $0.frames.isFinite && $0.frames > 0 && $0.frames <= 65535 }) else { return nil }
        let names = Dictionary(uniqueKeysWithValues: clips.enumerated().map { ($0.element.name, $0.offset) })
        guard OriginalLounge.animations.allSatisfy({ names[$0.name] != nil }) else { return nil }
        self.clips = clips; lookup = names
    }
    /// Original lookup 0x021931d0: only looping names acquire _o/_oe variants.
    public func clip(animation: Int, stage: OriginalLounge.AnimationStage = .main) -> Int? {
        guard OriginalLounge.animations.indices.contains(animation) else { return nil }
        let name = OriginalLounge.animations[animation].name
        if stage == .main { return lookup[name] }
        guard name.hasSuffix("_l") else { return nil }
        return lookup[String(name.dropLast(2)) + (stage == .exit ? "_oe" : "_o")]
    }
}

/// Native port of the ordinary animation transition/playback path. Wii U scene
/// graph calls are replaced by a numeric pose sample for our local renderer.
public struct OriginalLoungePlayback: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var clip: Int
        public var frame: Float
        public var previousClip: Int
        public var previousFrame: Float
        public var blend: Float
        public var revision: Int
        public var bridge: [Double] {
            [Double(clip), Double(frame), Double(previousClip), Double(previousFrame), Double(blend), Double(revision)]
        }
    }
    public private(set) var animation = 0
    public private(set) var stage = OriginalLounge.AnimationStage.main
    public private(set) var frame: Float = 0
    public private(set) var rate: Float = 1
    public private(set) var frameOffset: Float = 0
    public private(set) var blendWeight: Float = 1
    public private(set) var sample: Sample
    private var blendStep: Float = 0
    private var transitionBlend: Float = 0
    private var savedRate: Float = 1
    private var clip: Int

    public init(catalog: OriginalLoungeCatalog) {
        clip = catalog.clip(animation: 0)!
        sample = Sample(clip: clip, frame: 0, previousClip: clip, previousFrame: 0, blend: 1, revision: 0)
    }
    public var flags: UInt32 { OriginalLounge.animations[animation].flags }
    public func complete(_ catalog: OriginalLoungeCatalog) -> Bool {
        stage == .main && !catalog.clips[clip].loop && frame >= catalog.clips[clip].frames
    }
    public func canChange(to next: Int, catalog: OriginalLoungeCatalog) -> Bool {
        OriginalLounge.mayChangeAnimation(current: animation, requested: next, stage: stage,
            blendWeight: blendWeight, flags: flags, frame: frame, frameOffset: frameOffset,
            step: rate, length: catalog.clips[clip].frames)
    }
    /// 0x02194214 and the forced-rate path in 0x021947d4. The previous exit
    /// retains its old rate. Incoming entrance/main runs at the saved new rate.
    @discardableResult public mutating func request(_ next: Int, catalog: OriginalLoungeCatalog,
                                                   rate nextRate: Float = 1, blendOverride: Float = 0) -> Bool {
        guard nextRate.isFinite, nextRate > 0 else { return false }
        if next == animation { return false }
        guard canChange(to: next, catalog: catalog),
              let plan = OriginalLounge.transition(from: animation, to: next,
                previousHasExit: catalog.clip(animation: animation, stage: .exit) != nil,
                nextHasEntrance: catalog.clip(animation: next, stage: .entrance) != nil,
                blendOverride: blendOverride) else { return false }
        let previous = animation
        animation = next; stage = plan.stage; transitionBlend = plan.blendFrames
        savedRate = nextRate
        if stage == .exit {
            setClip(catalog.clip(animation: previous, stage: .exit)!, blend: 5)
        } else {
            setClip(catalog.clip(animation: next, stage: stage)!, blend: transitionBlend)
            rate = nextRate
        }
        return true
    }
    /// 0x02196b58: ongoing rate changes are separate from requesting an
    /// animation. Preserve the outgoing exit's rate, as the source does.
    public mutating func setRate(_ value: Float) {
        guard value.isFinite, value > 0 else { return }
        savedRate = value
        if stage != .exit { rate = value }
    }
    private mutating func setClip(_ next: Int, blend: Float) {
        sample.previousClip = sample.clip; sample.previousFrame = sample.frame
        sample.revision += 1
        clip = next; frame = 0; frameOffset = 0
        // 0x02192abc: linear weights, measured in controller updates.
        blendWeight = blend <= 0 ? 1 : 0
        blendStep = blend <= 0 ? 0 : 1 / blend
        sample.clip = next; sample.frame = 0; sample.blend = blendWeight
    }
    /// Stage advancement at the beginning of 0x021947d4. Entrances and exits
    /// must finish their clip and blend before advancing; entering the main
    /// loop uses the original five-update blend.
    public mutating func finishStages(catalog: OriginalLoungeCatalog) {
        guard stage != .main, !catalog.clips[clip].loop,
              frame >= catalog.clips[clip].frames, blendWeight >= 1 else { return }
        if stage == .exit, let entry = catalog.clip(animation: animation, stage: .entrance) {
            stage = .entrance; setClip(entry, blend: transitionBlend)
        } else {
            let blend: Float = stage == .entrance ? 5 : transitionBlend
            stage = .main; setClip(catalog.clip(animation: animation)!, blend: blend)
        }
        rate = savedRate
    }
    /// 0x02192808. One update advances the blend once, presents the current
    /// frame with optional scheduler catch-up, then advances stored playback.
    /// Tick cadence is supplied by the native host, not embedded in this port.
    public mutating func advance(catalog: OriginalLoungeCatalog, extraAdvance: Float = 0) {
        guard extraAdvance.isFinite, extraAdvance >= 0, extraAdvance <= 4 else { return }
        blendWeight = min(1, blendWeight + blendStep)
        frameOffset = extraAdvance
        let visibleFrame = frame + rate * extraAdvance
        let header = catalog.clips[clip]
        sample.clip = clip; sample.blend = blendWeight
        if header.loop {
            sample.frame = visibleFrame.truncatingRemainder(dividingBy: header.frames)
            if sample.frame < 0 { sample.frame += header.frames }
        } else { sample.frame = min(header.frames, max(0, visibleFrame)) }
        frame = visibleFrame + rate
        if header.loop {
            frame.formTruncatingRemainder(dividingBy: header.frames)
            if frame < 0 { frame += header.frames }
        } else { frame = min(header.frames, max(0, frame)) }
    }
}
