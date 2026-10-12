import Foundation

extension OriginalLounge {
    /// Decision block 0x02188b08...0x02189138 of LoungeMii's paired interaction
    /// update. All three initial draws occur, including on an ending action.
    public static func nextSocialAction(after current: Int, random: inout OriginalLoungeRandom) -> Int? {
        let first = random.unit(), second = random.unit(), third = random.unit()
        func dance(_ random: inout OriginalLoungeRandom) -> Int {
            if random.unit() < 0.07 { return 9 }
            return [3,5,7][Int(random.below(3))]
        }
        switch current {
        case 0:
            if first <= 0.1 { return 21 }
            if second <= 0.003 { return dance(&random) }
            return third <= 0.5 ? 1 : 2
        case 1,2:
            if first <= 0.7 { return current == 1 ? 2 : 1 }
            if second <= 0.1 { return 21 }
            if third <= 0.003 { return dance(&random) }
            return nil
        case 21,22:
            if first <= 0.4 { return current == 21 ? 22 : 21 }
            return second <= 0.5 ? 23 : 24
        case 23,24: return first <= 0.6 ? 21 : nil
        default: return nil
        }
    }
    public struct SocialTransition: Equatable, Sendable {
        public let action: Int
        public let partnerAction: Int
        public let durationTicks: Int
        public let rate: Float
    }
    /// The branch table at 0x0218914c sets the partner's complementary action and
    /// timer. Rock-paper-scissors uses original clip length and a shared random
    /// playback rate. The next turn's leader is the previous turn's partner.
    public static func socialTransition(action: Int, catalog: OriginalLoungeCatalog,
                                         random: inout OriginalLoungeRandom) -> SocialTransition? {
        guard let animation = socialAnimation(action: action), let clip = catalog.clip(animation: animation) else { return nil }
        var partner = action, duration = Int(catalog.clips[clip].frames)
        var rate: Float = 1
        switch action {
        case 0: partner = 0
        case 1,2: partner = action == 1 ? 2 : 1; duration = 180 + Int(random.below(120))
        case 3...18: partner = action % 2 == 1 ? action + 1 : action - 1; duration = 450 + Int(random.below(350))
        case 19,20: partner = action == 19 ? 20 : 19
        case 21,22:
            partner = action == 21 ? 22 : 21
            // 0x0218f918 uses a float range then double multiply/add and one
            // final float round. Preserve that order rather than an FMA guess.
            let range = Float(1.4) - Float(0.8)
            rate = Float(Double(random.unit()) * Double(range) + Double(Float(0.8)))
            duration = Int(Float(duration) * (1 / rate))
        case 23,24: partner = action == 23 ? 24 : 23; duration = 120
        default: return nil
        }
        return SocialTransition(action: action, partnerAction: partner, durationTicks: duration, rate: rate)
    }
    /// Social unlink cooldown in 0x021843e8. Values are update counts.
    public static func socialCooldown(random: inout OriginalLoungeRandom) -> Int {
        900 + Int(random.below(300))
    }
}
