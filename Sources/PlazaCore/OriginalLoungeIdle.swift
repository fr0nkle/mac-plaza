import Foundation

extension OriginalLounge {
    public struct IdleContext: Equatable, Sendable {
        public var role = 0
        public var current = 0
        public var idleTicks = 0
        public var groupDensity = 0
        public var preventsLyingDown = false // original group property +0x24
        public var specialAppealSuppressed = false // 0x0218a2ec
        public var groupActivity: Int? = nil // original +0x484, 128 means none
        public var disablesGroupActivities = false // +0x488
        public init() {}
    }
    public struct IdleSelection: Equatable, Sendable {
        public var baseline: Int
        public var intermediate: Int = 128
        public var intermediateTicks = 0
        public var followup: Int = 128
    }
    /// 0x02199fc8 + 0x0219a320, including draw order and rejected draws.
    /// Scene-dependent predicates are explicit host inputs, not guessed rules.
    public static func selectIdle(_ input: IdleContext, random: inout OriginalLoungeRandom) -> IdleSelection {
        var result = IdleSelection(baseline: 128)
        repeat {
            result.baseline = Int(random.next() >> 28) + 10
            if (input.role == 4 || input.role == 5) && !input.specialAppealSuppressed {
                result.baseline = [result.baseline, result.baseline, 46, 47][Int(random.next() >> 30)]
            }
        } while result.baseline == input.current
        if input.role == 4 || input.role == 5 { return result }
        let notSeated = !(34...45).contains(input.current)
        if notSeated && input.idleTicks > 600 && !input.preventsLyingDown {
            if random.unit() > 0.5 { result.baseline = 38; return result }
            result.baseline = 39 + Int(random.below(input.groupDensity < 4 ? 7 : 4))
            return result
        }
        let chance = random.unit()
        let restrictedBaseline = (26...33).contains(input.current) || (100...103).contains(input.current)
        if chance >= 0.3 && input.groupActivity == nil && !restrictedBaseline && notSeated { return result }
        // The source retries rejected choices. Xorshift's nonzero state ensures
        // this terminates; all accepted/rejected draws retain their source order.
        while true {
            var choice = Int(random.below(29))
            var imposed = false
            if let groupActivity = input.groupActivity, !input.disablesGroupActivities {
                var selected = groupActivity
                if (75...80).contains(selected) { selected = 75 + Int(random.below(6)) }
                choice = selected - 52; imposed = true
            }
            let probability = random.unit()
            switch choice {
            case 0:
                if probability > 0.5 { continue }
                if input.idleTicks > 300 && animations[input.current].flags & 1 != 0 {
                    result.intermediate = 50; result.followup = 51
                }
                return result
            case 1:
                guard random.below(3) == 0 else { continue }
                result.intermediate = 52
                result.followup = random.below(5) == 0 ? 61 : 53
                return result
            case 2...4, 7...16, 18:
                result.intermediate = choice + 52; return result
            case 5, 6:
                guard probability <= 0.5 else { continue }
                result.intermediate = choice + 52; return result
            case 17:
                guard probability <= 0.1 else { continue }
                result.intermediate = 69; return result
            case 19...28:
                if (!imposed && probability > 0.005) || input.disablesGroupActivities { continue }
                result.intermediate = choice + 52
                result.intermediateTicks = 1000 + Int(random.below(500))
                return result
            default: continue
            }
        }
    }

    /// Social controller's action-to-animation dispatch, 0x021947d4. Partner
    /// selection and advancement of these action codes are separate routines.
    public static func socialAnimation(action: Int) -> Int? {
        let ids = [111,112,113,114,115,116,117,118,119,120,121,114,115,116,117,118,119,120,121,122,123,124,125,126,127]
        return ids.indices.contains(action) ? ids[action] : nil
    }
}

/// Ordinary ambient path through 0x02199308/0x02198da0. Family arrival,
/// message-emotion and viewer reaction controllers are not claimed by this type.
public struct OriginalLoungeIdle: Equatable, Sendable {
    public private(set) var baseline = 10
    public private(set) var baselineTicks = 0
    public private(set) var holdingTicks = 0
    public private(set) var idleTicks = 0
    public private(set) var intermediate = 128
    public private(set) var followup = 128
    private var intermediateTicks = 0
    private var pendingBaseline = 128
    private var delayTicks = 0
    private var reactionTicks:Int? = nil
    public init() {}

    /// 02199c34: idle controller accepts the four source surprise clips only
    /// when the main stage is blended and can change. The later randomized
    /// surprise followups remain a host boundary; return to the held baseline.
    @discardableResult public mutating func react(_ reaction:OriginalLounge.CollisionReaction,
        playback:inout OriginalLoungePlayback,catalog:OriginalLoungeCatalog)->Bool {
        guard playback.stage == .main,playback.blendWeight>=1,reactionTicks==nil,
              playback.request(reaction.animation,catalog:catalog,rate:reaction.rate,blendOverride:reaction.blendFrames) else{return false}
        reactionTicks=60;return true
    }

    private mutating func enter(_ reset: Bool, playback: inout OriginalLoungePlayback,
                                catalog: OriginalLoungeCatalog, random: inout OriginalLoungeRandom) {
        if reset {
            baseline = pendingBaseline; baselineTicks = 0
            holdingTicks = OriginalLounge.holdTicks(animation: baseline, random: &random)
            delayTicks = 0
        }
        if intermediate < 128 {
            if playback.request(intermediate, catalog: catalog) {
                if !catalog.clips[catalog.clip(animation: intermediate)!].loop {
                    intermediateTicks = Int(catalog.clips[catalog.clip(animation: intermediate)!].frames)
                }
                return
            }
        } else if followup < 128 {
            if playback.request(followup, catalog: catalog) { return }
        } else if pendingBaseline < 128 {
            if playback.request(baseline, catalog: catalog) { pendingBaseline = 128 }
            return
        }
        clearSequence()
    }
    private mutating func clearSequence() {
        pendingBaseline = 128; intermediate = 128; intermediateTicks = 0; followup = 128
    }
    public mutating func step(playback: inout OriginalLoungePlayback, catalog: OriginalLoungeCatalog,
                              random: inout OriginalLoungeRandom, context: OriginalLounge.IdleContext) {
        let current = playback.animation
        if let ticks=reactionTicks {
            if (81...84).contains(current) {
                reactionTicks=ticks-1
                if ticks>0 || !playback.complete(catalog) {return}
            }
            reactionTicks=nil
        }
        if current == baseline {
            if context.groupActivity != nil { holdingTicks = min(holdingTicks, 300) }
            let age = baselineTicks; baselineTicks += 1
            if age >= holdingTicks {
                var input = context; input.current = baseline; input.idleTicks = idleTicks
                let selected = OriginalLounge.selectIdle(input, random: &random)
                pendingBaseline = selected.baseline; intermediate = selected.intermediate
                intermediateTicks = selected.intermediateTicks; followup = selected.followup
                enter(true, playback: &playback, catalog: catalog, random: &random)
            }
            idleTicks += 1; return
        }
        if current == intermediate {
            if playback.stage != .exit {
                intermediateTicks -= 1
                if intermediateTicks < 1 {
                    let blend: Float = intermediate == 52 && followup == 61 ? 40 : 0
                    intermediate = 128
                    if blend != 0, followup < 128 {
                        if playback.request(followup, catalog: catalog, blendOverride: blend) { return }
                        clearSequence(); return
                    }
                    enter(false, playback: &playback, catalog: catalog, random: &random)
                }
            }
            return
        }
        if current == followup {
            if playback.complete(catalog) {
                followup = 128; enter(false, playback: &playback, catalog: catalog, random: &random)
            }
            return
        }
        idleTicks = 0; baselineTicks = 0
        if current == 110 { delayTicks = min(delayTicks, 40) }
        guard playback.stage != .exit else { return }
        delayTicks -= 1
        guard delayTicks < 0 else { return }
        if !playback.complete(catalog) {
            guard catalog.clips[catalog.clip(animation: current)!].loop, playback.stage == .main,
                  playback.blendWeight >= 1 else { return }
            let draw = random.unit()
            if draw >= 0.02 && playback.flags & 4 == 0 { return }
        }
        if !(10...25).contains(baseline) { baseline = 10 }
        if playback.request(baseline, catalog: catalog) { clearSequence() }
    }
}
