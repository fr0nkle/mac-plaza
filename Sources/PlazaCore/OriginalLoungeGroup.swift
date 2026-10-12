import Foundation

extension OriginalLounge {
    /// 021922b0: original angular mask over the six adjacent group slots.
    /// Slot topology/occupancy comes from the host; Wii U atan uses host libm.
    public static func groupDirectionMask(_ direction: GroundPoint) -> UInt32 {
        let degrees = Float(atan2(Double(direction.x),Double(direction.z))*Double(Float(57.2957763671875))+360)
        let sector = (Int(degrees)%360)/60
        return (0..<6).contains(sector) ? [0x1c,0x0e,0x07,0x23,0x31,0x38][sector]:0x3f
    }
    /// 0219220c / 02192374: one bounded draw followed by a cyclic slot scan.
    /// Empty/disallowed slots consume no extra draws; this is not nearest-first.
    public static func groupNeighbor(slots: [Int?], mask: UInt32 = 0x3f,
                                     random: inout OriginalLoungeRandom) -> Int? {
        let start = Int(random.below(6))
        for offset in 0..<6 {
            let slot = (start+offset)%6
            if mask & (1<<slot) != 0, slots.indices.contains(slot), let actor = slots[slot] { return actor }
        }
        return nil
    }
    /// 0218e4ac/0218e580: the wider facing opportunity, before dance dispatch.
    public static func acceptsGroupFacing(_ actor: PartnerInput, at other: GroundPoint) -> Bool {
        guard !(1...7).contains(actor.animation), !actor.hasWatchTarget, !actor.hasPartner,
              actor.restrictions & 0x80 == 0, actor.socialTicks >= 0 else { return false }
        let dx = other.x-actor.position.x, dz = other.z-actor.position.z
        let forward = (dx*actor.forward.x).addingProduct(dz,actor.forward.z)
        return forward > 0 && (dx*dx).addingProduct(dz,dz) < 900
    }
    /// Refined source square-root operation, with a host reciprocal estimate.
    /// The remaining Float operations reproduce the original Newton step.
    static func groupRoot(_ value: Float) -> Float {
        guard value > 0 else { return 0 }
        let estimate = Double(1)/Double(value).squareRoot()
        let squared = Float(estimate*estimate), half = Float(estimate*0.5)
        let refinement = Float(3).addingProduct(-squared,value)
        return (refinement*half)*value
    }
    /// Automatic dance gate 0217f42c...0217f4e0. Invoked only after the
    /// ordinary facing opportunity failed; exactly one RNG draw is consumed.
    public static func automaticDanceGate(population: Int, random: inout OriginalLoungeRandom) -> Bool {
        let draw = random.unit()
        return draw < Float(0.009999999776482582)*groupRoot(groupRoot(Float(population)))
    }
    /// 0217ec38...0217edd4, idle facing bias. Three source draws; result degrees.
    public static func groupTurn(forward: GroundPoint, strength: Float = 0.7,
                                 random: inout OriginalLoungeRandom) -> Float {
        let facing = (forward.z+1)*0.5
        let bound = facing < 0.001 ? Float(0.001):min(facing,strength)
        let first = random.unit()*bound
        let reverse = first < random.unit()*strength
        let shift = Float(-15)*facing
        let low = Float(30)+shift, high = Float(45)+shift
        var angle = low.addingProduct(random.unit(),high-low)
        if forward.x > 0 { angle = -angle }
        if !reverse { angle = -angle }
        return angle
    }
}
