import Foundation

// Native ports from US Wii U Menu v277 (men.rpx SHA-256
// b67deb8fb36889fd5451b89a5b1ce06b31abe341960c3bf1df84e9df4bbe1474).
// Addresses identify original routines; names below describe recovered semantics.
// Animation, idle and paired action scheduling are active in the native host.
// Native geometry, admission, owner callbacks and full global dispatch remain host boundaries.

public struct OriginalLoungeRandom: Equatable, Sendable {
    public private(set) var words: [UInt32]

    /// Original seed expansion, 0x02454a98. The menu's wall-clock seed is a host input.
    public init(seed: UInt32) {
        var value = seed
        words = (1...4).map { ordinal in
            value = (value ^ (value >> 30)) &* 0x6c078965 &+ UInt32(ordinal)
            return value
        }
    }

    /// Original xorshift128 update, 0x02454b34. All arithmetic wraps at 32 bits.
    public mutating func next() -> UInt32 {
        let t = words[0] ^ (words[0] << 11)
        let result = words[3] ^ (words[3] >> 19) ^ t ^ (t >> 8)
        words = [words[1], words[2], words[3], result]
        return result
    }

    /// Original bounded draw uses the high product, never modulo (0x0218a88c).
    public mutating func below(_ upper: UInt32) -> UInt32 {
        UInt32((UInt64(next()) * UInt64(upper)) >> 32)
    }

    /// Preserve the original float rounding, including a possible rounded value of 1.
    public mutating func unit() -> Float { Float(next()) * 0x1p-32 }
}

public enum OriginalLounge {
    /// Positional 12-bit action mask parser, 0x021902d4.
    public static func actionMask(_ bytes: [UInt8]) -> UInt16 {
        var result: UInt16 = 0
        for (index, byte) in bytes.prefix(12).enumerated() {
            if byte == 0 { break }
            let expected = index < 9 ? index + 49 : index + 56
            if Int(byte) == expected { result |= UInt16(1) << index }
        }
        return result
    }

    /// 0x02183104. Field names deliberately retain original offsets where the
    /// higher-level meaning has not been recovered; no guessed inputs are hidden.
    public struct RestrictionInput: Equatable, Sendable {
        public var forcedAnimation: Int32 = -1  // Mii +0x280
        public var flag288 = false
        public var flag289 = false
        public var movementState: Int32 = 0    // +0x2e8
        public var has3b4 = false
        public var has3a0 = false
        public var animationFlags: UInt32 = 0  // controller +0x20
        public var animationID: Int32 = 0      // controller +0x08
        public var category: Int32 = 0         // Mii +0x48c
        public init() {}
    }

    public static func restrictions(_ input: RestrictionInput) -> UInt32 {
        var flags: UInt32 = 0
        if input.forcedAnimation >= 0 {
            flags = (46...49).contains(input.forcedAnimation) ? 0xe0 : 0xe8
            if (34...37).contains(input.forcedAnimation) { flags = 0xf8 }
        }
        if input.flag288 || input.flag289 || input.movementState == 4 || input.movementState == 5 { flags |= 0xab }
        if input.has3b4 { flags |= 0x4ab }
        if input.flag289 { flags |= 0x400 }
        if input.animationFlags & 8 == 0 { flags |= 0x100 }
        if input.animationFlags & 16 == 0 || input.flag289 { flags |= 0x200 }
        if (50...70).contains(input.animationID) || input.has3a0 { flags |= 0x40 }
        if input.category < 3 { flags |= 0x28 }
        if (88...99).contains(input.animationID) { flags |= 0x48 }
        if (50...53).contains(input.animationID) { flags |= 0x4d }
        if (46...49).contains(input.animationID) { flags &= 0xffffffe7 }
        return flags
    }

    public enum AnimationStage: Int, Sendable { case exit, entrance, main }

    public struct Transition: Equatable, Sendable {
        public var stage: AnimationStage
        public var blendFrames: Float
        public var interrupts: Bool
        public var playsPreviousExit: Bool { stage == .exit }
    }

    /// Recovered decision block 0x02194214...0x02194458. The original lookup
    /// supplies presence of *_oe and *_o; clip data remains in the local resource.
    public static func transition(from previous: Int, to next: Int,
                                  previousHasExit: Bool, nextHasEntrance: Bool,
                                  blendOverride: Float = 0) -> Transition? {
        guard animations.indices.contains(previous), animations.indices.contains(next),
              blendOverride.isFinite else { return nil }
        let incoming = animations[next]
        let outgoing = animations[previous]
        let interrupts = (1...7).contains(next) || (81...84).contains(next)
        let useExit = previousHasExit && (!interrupts || (34...45).contains(previous))
        let stage: AnimationStage = useExit ? .exit : nextHasEntrance ? .entrance : .main
        var blend = blendOverride == 0 || interrupts ? incoming.blendFrames : blendOverride
        if outgoing.blendLimit > 0 { blend = max(blend, outgoing.blendLimit) }
        if outgoing.blendLimit < 0 { blend = min(blend, -outgoing.blendLimit) }
        return Transition(stage: stage, blendFrames: blend, interrupts: interrupts)
    }

    /// Original zero-crossing test used by 0x02196a30. Inputs are source frames,
    /// not seconds. A flagged looping action releases at its wrap boundary.
    public static func crossesBoundary(frame: Float, frameOffset: Float,
                                       step: Float, length: Float) -> Bool {
        guard frame.isFinite, frameOffset.isFinite, step.isFinite,
              length.isFinite, length > 0 else { return false }
        let next = frame + step
        if frame - frameOffset >= 0 {
            return !(next > 0 && next - length < 0)
        }
        return !(next < 0 && next + length > 0)
    }

    /// 0x02196a30's guards, before calling the transition routine.
    public static func mayChangeAnimation(current: Int, requested: Int, stage: AnimationStage,
                                          blendWeight: Float, queuedA: Int = 128, queuedB: Int = 128,
                                          flags: UInt32, frame: Float, frameOffset: Float,
                                          step: Float, length: Float) -> Bool {
        guard current != requested, animations.indices.contains(requested), stage == .main,
              blendWeight >= 1, queuedA >= 128, queuedB >= 128 else { return false }
        return flags & 4 == 0 || crossesBoundary(frame: frame, frameOffset: frameOffset,
                                                step: step, length: length)
    }

    /// 0x02198da0, original holding-time draws, in controller ticks.
    public static func holdTicks(animation: Int, random: inout OriginalLoungeRandom) -> Int {
        let ordinary = Int(random.below(900)) + 300
        // The ordinary draw still happens when a seated draw replaces it.
        return (34...45).contains(animation) ? Int(random.below(1200)) + 1200 : ordinary
    }

    /// Ordinary standing baseline choice from 0x02199fc8. Specialized family
    /// and special-character branches are separate work, not approximated here.
    public static func standingIdle(after previous: Int, random: inout OriginalLoungeRandom) -> Int {
        var selected: Int
        repeat { selected = Int(random.next() >> 28) + 10 } while selected == previous
        return selected
    }

    public struct Animation: Equatable, Sendable {
        public let name: String
        public let blendFrames: Float
        public let blendLimit: Float
        public let flags: UInt32
    }
    // The verified original descriptor table at 0x100f43f8, 128 × 24 bytes.
    // Populated below by scripts/recover-lounge.py's source-table export.
    public static let animations: [Animation] = animationTable
}
