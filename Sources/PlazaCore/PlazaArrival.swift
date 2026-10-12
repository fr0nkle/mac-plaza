import Foundation

/// Native choreography for a newly confirmed Mii, using the crowd's own actor.
public enum PlazaArrival {
    public static let center = CrowdPoint(0.5, 0.55)
    public static let landing = 0.8
    public static let zoomIn = 1.45
    public static let pullback = 4.2
    public static let duration = 7.6
    public enum Cue: String, CaseIterable, Sendable {
        case drop = "arrival-drop", wave = "arrival-wave"
        public var time:Double { self == .drop ? PlazaArrival.landing:PlazaArrival.landing+0.32 }
    }

    public static func height(at elapsed: Double) -> Double {
        let t = max(0, elapsed)
        if t < landing { return 8 * (1 - pow(t / landing, 2)) }
        let bounce = min(1, (t - landing) / 0.32)
        return 0.22 * sin(bounce * .pi)
    }

    public static func focus(at elapsed: Double) -> Double {
        func smooth(_ value: Double) -> Double {
            let t = min(1, max(0, value))
            // Zero velocity and acceleration at both ends, including the hold.
            return t * t * t * (10 + t * (-15 + 6 * t))
        }
        return smooth(elapsed / zoomIn) * (1 - smooth((elapsed - pullback) / (duration - pullback)))
    }
}
