import Foundation

extension OriginalLounge {
    public struct CollisionReaction:Equatable,Sendable {
        public let type:Int
        public let rate:Float
        public var animation:Int {81+type}
        public var blendFrames:Float {type>=2 ? 10/(rate*rate):0}
    }
    /// Standing-actor reaction branch 02186e40...02187368. Call only after
    /// contact with a running actor (animation 4...6). Owner locks, collision
    /// queries and movement-request ownership are supplied by the Mac adapter.
    public static func collisionReaction(delta:GroundPoint,forward:GroundPoint,velocity:GroundPoint,
        restrictions:UInt32=0)->CollisionReaction? {
        guard restrictions&4==0 else{return nil}
        let d=normalizedGround(delta)
        let alignment=abs((forward.z*d.z).addingProduct(forward.x,d.x))
        let closing = -((forward.z*velocity.z).addingProduct(forward.x,velocity.x)*alignment)
        let lateral=(d.z*velocity.x-d.x*velocity.z)*(1-alignment)
        func clamp(_ x:Float)->Float {min(1,max(0,x))}
        // The source type-0 gain is its live zero register, so rate stays 1.
        if closing>0.800000011920929 {return .init(type:0,rate:1)}
        if closing < -0.5 {return .init(type:1,rate:Float(1).addingProduct(0.2999999523162842,clamp((-closing-0.5)/0.7000000476837158)))}
        guard abs(lateral)>0.019999999552965164 else{return nil}
        let amount=abs(lateral)
        let rate:Float = amount>=0.20000000298023224
            ? Float(1).addingProduct(0.2999999523162842,clamp((amount-0.20000000298023224)/0.6000000238418579))
            : Float(0.5).addingProduct(0.5,clamp((amount-0.019999999552965164)/0.18000000715255737))
        return .init(type:lateral>0 ? 2:3,rate:rate)
    }
    /// Actor constructor 02183ab4, with the owner-forced style supplied by host.
    public static func runStyle(forceStyleOne:Bool=false,random:inout OriginalLoungeRandom)->Int {
        if forceStyleOne || random.unit()<0.004999999888241291 {return 1}
        return random.unit()<0.004999999888241291 ? 2:0
    }
}
