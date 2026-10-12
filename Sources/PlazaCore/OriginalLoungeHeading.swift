import Foundation

/// Scalar heading update from 0x02186808…0x02186a08. The host supplies the
/// bearing in radians; the Wii U atan/table-based matrix construction is not
/// executed. Float round points and the original fused operations are retained.
public struct OriginalLoungeHeading: Equatable, Sendable {
    public var angle: Float = 0
    public private(set) var delta: Float = 0
    public var lean: Float = 0
    public var accumulatedDegrees: Float = 0
    public init(angle: Float = 0, lean: Float = 0, accumulatedDegrees: Float = 0) {
        self.angle = angle; self.lean = lean; self.accumulatedDegrees = accumulatedDegrees
    }

    public mutating func step(toward bearing: Float, gain: Float, limit: Float) {
        guard bearing.isFinite, angle.isFinite, lean.isFinite, accumulatedDegrees.isFinite,
              abs(bearing) <= 65536, abs(angle) <= 65536,
              gain.isFinite, (0...1).contains(gain), limit.isFinite, (0...4).contains(limit) else { return }
        let turn: Float = 6.2831854820251465
        let pi: Float = 3.1415927410125732
        let difference = bearing - angle
        let revolutions = Float(Int(difference / turn))
        var offset = Float(Double(difference) - Double(revolutions) * Double(turn))
        while offset > pi { offset -= turn }
        while offset < -pi { offset += turn }
        offset = (angle + offset) - angle
        offset = min(limit, max(-limit, offset))
        let old = angle
        let roundedOffset = (old + offset) - old
        angle = Float(Double(roundedOffset) * Double(gain) + Double(old))
        delta = angle - old
        let quadratic = Float(250) * (delta * delta)
        let desiredLean = Float(Double(15) * Double(delta) + Double(quadratic))
        accumulatedDegrees = Float(Double(delta) * Double(Float(57.2957763671875)) + Double(accumulatedDegrees))
        lean = (lean - min(8, max(-8, desiredLean))) * Float(0.9200000166893005)
        if abs(lean) < Float(0.10000000149011612) { lean = 0 }
    }
}
