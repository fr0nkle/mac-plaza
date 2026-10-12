import Foundation

extension OriginalLounge {
    /// Ground coordinates in menu model units, independent of the Mac viewport.
    public struct GroundPoint: Equatable, Sendable {
        public var x: Float
        public var z: Float
        public init(_ x: Float, _ z: Float) { self.x = x; self.z = z }
    }
    public struct PartnerInput: Sendable {
        public var position: GroundPoint
        public var forward: GroundPoint
        public var animation: Int
        public var hasWatchTarget = false
        public var hasPartner = false
        public var restrictions: UInt32 = 0
        public var socialTicks = 0
        public init(position: GroundPoint, forward: GroundPoint, animation: Int) {
            self.position = position; self.forward = forward; self.animation = animation
        }
    }
    /// 0x0218e378. The caller 0x0218e458 requires this in BOTH directions.
    /// Blend weight and stage are deliberately absent from the source predicate.
    public static func acceptsPartner(_ actor: PartnerInput, at other: GroundPoint) -> Bool {
        guard (10...25).contains(actor.animation), !actor.hasWatchTarget, !actor.hasPartner,
              actor.restrictions & 0x80 == 0, actor.socialTicks >= 0 else { return false }
        let dx = other.x - actor.position.x, dz = other.z - actor.position.z
        let forward = (dx * actor.forward.x).addingProduct(dz, actor.forward.z)
        let squared = (dx * dx).addingProduct(dz, dz)
        return forward > 0 && squared < 324 && Float(0.1224999949336052) * squared <= forward * forward
    }
    public struct SocialStart: Equatable, Sendable {
        public let firstAction: Int
        public let secondAction: Int
        public let firstLeader: Bool
        public let durationTicks: Int
    }
    /// 0x0218e60c...0x0218e768: sign draw, then bow/talk draw, then
    /// a duration draw only for talk. Bow length comes from the original clip.
    public static func startSocial(bowFrames: Float, random: inout OriginalLoungeRandom) -> SocialStart {
        let leader = Int32(bitPattern: random.next()) >= 0
        if random.unit() <= 0.3 {
            return SocialStart(firstAction: 0, secondAction: 0, firstLeader: leader, durationTicks: Int(bowFrames))
        }
        return SocialStart(firstAction: leader ? 1 : 2, secondAction: leader ? 2 : 1,
                           firstLeader: leader, durationTicks: 180 + Int(random.below(120)))
    }
    /// Side-by-side dance eligibility, 0x0218e7f4. Both stand facing the
    /// plaza front, with the second actor to the first actor's right.
    public static func acceptsDance(_ first: PartnerInput, _ second: PartnerInput) -> Bool {
        func ready(_ actor: PartnerInput) -> Bool {
            (10...25).contains(actor.animation) && !actor.hasWatchTarget && !actor.hasPartner &&
                actor.restrictions & 0x80 == 0 && actor.socialTicks >= 0
        }
        guard ready(first), ready(second), first.forward.z + second.forward.z > 1,
              (first.forward.x * second.forward.x).addingProduct(first.forward.z,second.forward.z) > 0.6 else { return false }
        let dx = second.position.x-first.position.x, dz = second.position.z-first.position.z
        let length = (dx * dx).addingProduct(dz,dz).squareRoot()
        guard length > 7, length < 17 else { return false }
        let nx = dx/length, nz = dz/length
        return nx >= 0.5 && (nx * first.forward.z).addingProduct(-nz,first.forward.x) >= 0.4 &&
            (nx * second.forward.z).addingProduct(-nz,second.forward.x) >= 0.4
    }
    /// 0x0218e99c...0x0218ebac. Orbit dance choices have their own source
    /// selector, distinct from the conversation's in-place dances.
    public static func startDance(random: inout OriginalLoungeRandom) -> SocialStart {
        let duration = 450 + Int(random.below(350))
        let action: Int
        if random.unit() < 0.07 { action = 18 }
        else if random.unit() < 0.02 { action = 20 }
        else { action = [12,14,16][Int(random.below(3))] }
        return SocialStart(firstAction:action,secondAction:action-1,firstLeader:true,durationTicks:duration)
    }
    /// 0x02188344...0x021884fc / 0x021887d4...0x02188978.
    /// Source fctiwz truncates the frame difference before the integer remainder.
    public static func pairedRate(frame: Float, partnerFrame: Float, length: Float) -> Float {
        guard length.isFinite, (1...65535).contains(length), frame.isFinite, partnerFrame.isFinite,
              abs(frame) <= 65535, abs(partnerFrame) <= 65535 else { return 1 }
        let count = Int(length)
        guard count > 0 else { return 1 }
        let gap = (Int(frame - partnerFrame) + count) % count
        return gap > 6 && Float(gap) < Float(count) * 0.5 ? 0.7 : 1
    }
    public struct DancePosition: Equatable, Sendable {
        public let position: GroundPoint
        public let tangent: GroundPoint
        public let headingGain: Float
    }
    /// Orbit/root block 0x021884fc...0x021887bc. The original SDK vector
    /// normalization and reciprocal-square-root estimate use host sqrt here.
    /// All source distances, phase pulse, direction and gains are retained.
    public static func dancePosition(action: Int, position: GroundPoint, partner: GroundPoint,
                                     mainFrame: Float, length: Float) -> DancePosition? {
        guard (11...20).contains(action), length.isFinite, length > 0, mainFrame.isFinite,
              position.x.isFinite, position.z.isFinite, partner.x.isFinite, partner.z.isFinite else { return nil }
        let dx = partner.x - position.x, dz = partner.z - position.z
        let squared = (dx * dx).addingProduct(dz, dz), distance = squared.squareRoot()
        let nx = distance > 0 ? dx / distance : 0, nz = distance > 0 ? dz / distance : 0
        let influence: Float = 1 - min(1, abs((mainFrame / length) * 4 - 3))
        let error = distance - ((13...14).contains(action) ? 11 : 9)
        let correction = abs(error).squareRoot() * 0.01 * influence * (error < 0 ? -1 : 1)
        let next = GroundPoint(position.x + nx * correction, position.z + nz * correction)
        let tangent = action % 2 == 1 ? GroundPoint(nz, -nx) : GroundPoint(-nz, nx)
        return DancePosition(position: next, tangent: tangent, headingGain: 0.1 * influence)
    }
    public struct NavigationObstacle: Sendable {
        public let center: GroundPoint
        public let radius: Float
        public init(center: GroundPoint, radius: Float) { self.center = center; self.radius = radius }
    }
    /// Host implementation of the SDK point-to-segment squared distance.
    static func segmentDistanceSquared(_ point: GroundPoint, _ a: GroundPoint, _ b: GroundPoint) -> Float {
        let dx = b.x - a.x, dz = b.z - a.z
        let squared = (dx * dx).addingProduct(dz, dz)
        let t = squared > 0 ? min(1, max(0, ((point.x-a.x)*dx + (point.z-a.z)*dz) / squared)) : 0
        let x = point.x - a.x.addingProduct(t, dx), z = point.z - a.z.addingProduct(t, dz)
        return (x * x).addingProduct(z, z)
    }
    /// Destination search 0x021ad1e4...0x021ad5d4. Ten ACCEPTED samples,
    /// nearest preferred squared distance; rejected obstacle paths relax only
    /// that obstacle's clearance. Roles 1/2/3 use the original 150 x 130 ellipse.
    /// Host bounds/obstacles replace the menu database, libm replaces its trig
    /// table/pow, and 1024 attempts bound pathological local layouts.
    public static func destination(from current: GroundPoint, role: Int, halfWidth: Float, halfDepth: Float,
                                   obstacles: [NavigationObstacle], random: inout OriginalLoungeRandom) -> GroundPoint? {
        guard halfWidth > 0, halfDepth > 0, halfWidth.isFinite, halfDepth.isFinite,
              current.x.isFinite, current.z.isFinite else { return nil }
        let special = (1...3).contains(role)
        let preferred = Float(50).addingProduct(random.unit(), special ? 100 : 250)
        let preferredSquared = preferred * preferred
        // The source database has at most eleven item circles.
        let circles = Array(obstacles.prefix(11))
        var clearance = circles.map { circle -> Float in
            let dx = current.x-circle.center.x, dz = current.z-circle.center.z, radius = circle.radius * Float(0.8)
            return min((dz * dz).addingProduct(dx, dx), radius * radius)
        }
        var best: GroundPoint?, score = Float.greatestFiniteMagnitude, accepted = 0
        for _ in 0..<1024 {
            let candidate: GroundPoint
            if special {
                let theta = random.unit() * (2 * Float.pi), radial = pow(random.unit(), Float(0.3))
                candidate = GroundPoint((sin(theta) * radial) * 150, Float(20).addingProduct(cos(theta) * radial, 130))
            } else {
                let x = random.unit() * (halfWidth + halfWidth) - halfWidth
                let z = (-halfDepth).addingProduct(random.unit(), halfDepth + halfDepth)
                candidate = GroundPoint(x, z)
            }
            var rejected = false
            for j in circles.indices {
                if segmentDistanceSquared(circles[j].center, current, candidate) - clearance[j] < 0 {
                    clearance[j] *= 0.9; rejected = true; break
                }
            }
            if rejected { continue }
            let dx = candidate.x-current.x, dz = candidate.z-current.z
            let cost = abs(preferredSquared - (dz * dz).addingProduct(dx, dx))
            if cost < score { best = candidate; score = cost }
            accepted += 1
            if accepted == 10 { break }
        }
        return best
    }
    /// Circle-overlap extrema reduction from 0x021a5660. The host supplies
    /// neighboring circles/radii; sqrt replaces Espresso's refined estimate.
    public static func separation(position: GroundPoint, radius: Float, neighbors: [NavigationObstacle]) -> GroundPoint {
        var minX: Float = 0, maxX: Float = 0, minZ: Float = 0, maxZ: Float = 0
        for other in neighbors {
            let dx = position.x-other.center.x, dz = position.z-other.center.z, sum = radius+other.radius
            let squared = (dx * dx).addingProduct(dz, dz)
            guard squared < sum * sum else { continue }
            let distance = squared.squareRoot()
            let x: Float, z: Float
            if distance > 0 { let scale = sum / distance - 1; x = scale * dx; z = scale * dz }
            else { x = 0; z = sum }
            minX = min(minX, x); maxX = max(maxX, x); minZ = min(minZ, z); maxZ = max(maxZ, z)
        }
        return GroundPoint(minX + maxX, minZ + maxZ)
    }
}
