import Foundation

/// Locomotion states of 0x02184b24 and collision integration of 0x02187574.
/// Coordinates/displacements are in source model units per controller update.
/// The Mac host supplies paths, collider results, body proportions and cadence.
public struct OriginalLoungeMotion: Equatable, Sendable {
    public var speed: Float = 0
    public var direction = OriginalLounge.GroundPoint(0,1)
    public var ramp: Float = 0 // actor +348
    public var target = OriginalLounge.GroundPoint(0,0) // actor +308/+310
    public var walking = false
    public var collision = OriginalLoungeCollision()
    public var displacement = OriginalLounge.GroundPoint(0,0)
    public var gaitDistance: Float = 0
    public enum State:Int,Sendable {case rest,walk,run,tired,fall,recover,blowOut}
    public var state:State = .rest // +2e8
    public var stateTicks=0 // +2ec
    public var runCooldown=0 // +324
    public var runStyle=0 // +278, supplied by the actor's source role
    public init() {}

    /// State-1 speed/direction block, 0x02185250...0x02185578. The original
    /// parameter +328 is zero for ordinary unassigned wandering (02186660).
    public mutating func walk(toward delta: OriginalLounge.GroundPoint,
                              forward: OriginalLounge.GroundPoint,
                              height: Float = 0.5, urgency: Float = 0,
                              special: Bool = false, turnFactor: Float = 1,
                              running: Bool = false, assigned: Bool = false) {
        let squared = (delta.z * delta.z).addingProduct(delta.x,delta.x)
        guard squared > 0 else { return }
        let length = squared.squareRoot()
        let inverse: Float = 1/length
        let desired = OriginalLounge.GroundPoint(delta.x*inverse,delta.z*inverse)
        let alignment = (direction.z*desired.z).addingProduct(direction.x,desired.x)
        let maximum: Float = height < 0.5 ? Float(0.2199999988079071).addingProduct(0.030000001192092896,height+height):0.25
        let low:Float = running ? (assigned ? 0.8999999761581421:0.5):0.15000000596046448
        let high:Float = running ? (assigned ? 1.2999999523162842:0.800000011920929):maximum
        let desiredSpeed = low.addingProduct(high-low,min(1,length/(running ? 200:50)))
        var steering: Float = 1, damping: Float = 1
        if alignment < 0.699999988079071 {
            steering = special ? 1:Float(1).addingProduct(-0.8999999761581421,urgency)
            damping = special ? 0.9300000071525574:Float(0.9300000071525574).addingProduct(0.06999999284744263,urgency)
            if alignment >= 0 {
                let t = alignment/Float(0.699999988079071)
                steering = Float(1).addingProduct(-(1-steering),Float(1).addingProduct(-t,t))
                damping = Float(1).addingProduct(-(1-damping),1-t)
                if !special {
                    steering = steering.addingProduct(1-steering,urgency)
                    damping = damping.addingProduct(1-damping,urgency)
                }
            }
        }
        if turnFactor < 1 {
            var factor = turnFactor.addingProduct(1-turnFactor,0.5)
            if !special { factor = factor.addingProduct(1-factor,urgency) }
            steering *= factor
        }
        if ramp < 1 {
            ramp = min(1,ramp+Float(0.003000000026077032))
            let factor = special ? ramp:ramp.addingProduct(1-ramp,urgency)
            steering *= factor
        }
        if steering >= 1 { direction = desired }
        else {
            direction.x = direction.x.addingProduct(desired.x-direction.x,steering)
            direction.z = direction.z.addingProduct(desired.z-direction.z,steering)
            direction = OriginalLounge.normalizedGround(direction)
        }
        let dot = (forward.x*direction.x).addingProduct(forward.z,direction.z)
        var cap = Float(0.0010000000474974513).addingProduct(0.003999999724328518,0.5*(dot+1))
        if !special { cap = cap.addingProduct(0.019999999552965164-cap,urgency) }
        speed *= damping
        let gain = special ? Float(0.029999999329447746):Float(0.029999999329447746).addingProduct(0.12000000476837158,urgency)
        speed += min(cap,(desiredSpeed-speed)*gain)
    }
    /// Compatibility entry for ordinary walking only. The crowd uses locomote.
    public mutating func step(position: OriginalLounge.GroundPoint, goal: OriginalLounge.GroundPoint,
                              forward: OriginalLounge.GroundPoint, frame: Float, length: Float,
                              height: Float = 0.5, canWalk: Bool = true) -> OriginalLounge.GroundPoint {
        target.x = target.x.addingProduct(goal.x-target.x,0.05)
        target.z = target.z.addingProduct(goal.z-target.z,0.05)
        let delta = OriginalLounge.GroundPoint((target.x-position.x)*collision.speedScale,(target.z-position.z)*collision.speedScale)
        let squared = (delta.z*delta.z).addingProduct(delta.x,delta.x)
        if !walking && squared > 36 && canWalk { walking = true; direction = forward }
        if walking && squared < 36 {
            let radius = OriginalLounge.walkStopRadius(frame:frame,length:length)
            if squared < radius*radius { walking = false }
        }
        if walking && canWalk { walk(toward:delta,forward:forward,height:height) }
        else { speed = 0 }
        displacement = .init(direction.x*speed,direction.z*speed)
        gaitDistance = max(0,(displacement.x*forward.x).addingProduct(displacement.z,forward.z))
        return displacement
    }
    /// 02184b24 state decisions and speed blocks; animation readiness, role,
    /// completion and group ownership are supplied explicitly by the host.
    public mutating func locomote(position:OriginalLounge.GroundPoint,goal:OriginalLounge.GroundPoint,
        forward:OriginalLounge.GroundPoint,frame:Float,length:Float,height:Float=0.5,
        urgency:Float=0,special:Bool=false,assigned:Bool=false,canStart:Bool=true,
        animation:Int=3,animationComplete:Bool=false,random:inout OriginalLoungeRandom)->OriginalLounge.GroundPoint {
        stateTicks+=1
        target.x=target.x.addingProduct(goal.x-target.x,0.05)
        target.z=target.z.addingProduct(goal.z-target.z,0.05)
        let delta=OriginalLounge.GroundPoint((target.x-position.x)*collision.speedScale,(target.z-position.z)*collision.speedScale)
        let squared=(delta.z*delta.z).addingProduct(delta.x,delta.x)
        decide(squaredDistance:squared,frame:frame,length:length,urgency:urgency,special:special,
            assigned:assigned,canStart:canStart,animation:animation,animationComplete:animationComplete,random:&random)
        switch state {
        case .rest,.recover:speed=0
        case .walk,.run:
            if state != .walk || canStart {
                walk(toward:delta,forward:forward,height:height,urgency:urgency,special:special,
                     running:state == .run,assigned:assigned)
            } else {speed=0}
        case .tired:speed *= speed>0.800000011920929 ? Float(0.9700000286102295):0.9950000047683716
        case .fall:speed *= stateTicks<11 ? Float(1.0099999904632568):0.9300000071525574
        case .blowOut:speed *= stateTicks<61 ? Float(0.9800000190734863):0.9300000071525574
        }
        walking=state != .rest && state != .recover
        displacement = .init(direction.x*speed,direction.z*speed)
        gaitDistance=max(0,(displacement.x*forward.x).addingProduct(displacement.z,forward.z))
        return displacement
    }
    /// The decision prefix ends at 021851f8, before the speed update. Kept
    /// separate so instruction fixtures can test RNG draws and state changes.
    public mutating func decide(squaredDistance:Float,frame:Float,length:Float,urgency:Float=0,
        special:Bool=false,assigned:Bool=false,canStart:Bool=true,animation:Int=3,
        animationComplete:Bool=false,random:inout OriginalLoungeRandom) {
        runCooldown-=1
        func change(_ next:State) {if state != next {state=next;stateTicks=0}}
        switch state {
        case .rest:
            let radius:Float = special ? 6:6*(1-urgency)
            if squaredDistance>radius*radius && canStart {change(.walk)}
        case .walk:
            if !special && runCooldown<0 {
                let radius:Float = assigned ? 50*(1-urgency):200
                if squaredDistance>radius*radius {change(.run);break}
            }
            if squaredDistance<36 {
                let radius=(3...7).contains(animation) ? OriginalLounge.walkStopRadius(frame:frame,length:length):2
                if squaredDistance<radius*radius {change(.rest)}
            }
        case .run:
            var changed=false
            if speed>(runStyle == 3 ? 1:1.2000000476837158) {
                let chance=random.unit()*200
                if chance<(runStyle == 3 ? 0.004999999888241291:0.0020000000949949026),animation==4 {
                    change(.fall);changed=true
                }
            }
            if !changed && speed>0.800000011920929 {
                let chance=random.unit()*200
                if chance<(runStyle == 3 ? 0.029999999329447746:0.019999999552965164) {
                    change(.tired);changed=true
                }
            }
            if !changed {
                let radius:Float = assigned ? 40:80
                if squaredDistance<radius*radius {change(.walk)}
            }
        case .tired:
            if speed<0.5 {speed=0.5;change(.blowOut)}
        case .fall:
            if animation==1 && animationComplete {change(.recover)}
        case .recover:
            if animation==60 && animationComplete {change(.walk)}
        case .blowOut:
            if animation==2 && animationComplete {change(.walk);runCooldown=300}
        }
    }
    public var requestedAnimation:Int {
        switch state {
        case .rest:return 0
        case .walk:return 3
        case .run:return runStyle == 2 ? 6:runStyle == 1 ? 5:4
        case .tired:return 7
        case .fall:return 1
        case .recover:return 60
        case .blowOut:return 2
        }
    }
    /// 02196e04: ordinary forward gait plus the filtered collision contribution.
    public func animationRate(stature:Float)->Float {
        let gait=max(0,gaitDistance/max(0.001,stature)+collision.gait)
        switch requestedAnimation {
        case 3:return min(0.4,max(0.15,gait))*3.846153974533081
        case 4...6:return min(1.4,max(0.75,gait))*1.0752688646316528
        case 7:return min(1.4,max(0.3,gait))*2.0833334922790527
        default:return 1
        }
    }
}

public struct OriginalLoungeCollision: Equatable, Sendable {
    public var impulse = OriginalLounge.GroundPoint(0,0) // +370/+378
    public var previous = OriginalLounge.GroundPoint(0,0) // +37c/+384
    public var speedScale: Float = 1 // +318
    public var gait: Float = 0 // +334
    public private(set) var reactionDelta:OriginalLounge.GroundPoint? = nil
    public init() {}
    /// 02186c64...02186dbc, excluding owner locks and the later animation
    /// reaction/avoidance-angle branches. Relative movement is the prior tick's
    /// displacement. SDK vector normalization/length use host sqrt.
    public mutating func contact(_ correction: OriginalLounge.GroundPoint,
                                 direction: OriginalLounge.GroundPoint,
                                 neighborDelta: OriginalLounge.GroundPoint? = nil,
                                 relativeMovement: OriginalLounge.GroundPoint = .init(0,0),
                                 neighborMovable: Bool = true) -> (OriginalLounge.GroundPoint,Bool) {
        var value = correction
        reactionDelta=neighborDelta
        if neighborDelta != nil && neighborMovable { value.x *= 0.5; value.z *= 0.5 }
        let opposed = (value.x*direction.x).addingProduct(value.z,direction.z) < 0
        func filtered(_ current: Float, _ previous: Float) -> Float {
            guard current*previous < 0 else { return current }
            let sum = current+previous
            return -(sum*current) < 0 ? sum:0
        }
        value.x = filtered(value.x,previous.x); value.z = filtered(value.z,previous.z)
        if let delta = neighborDelta, relativeMovement.x != 0 || relativeMovement.z != 0 {
            let movement = OriginalLounge.normalizedGround(relativeMovement)
            let dot = (delta.x*movement.x).addingProduct(delta.z,movement.z)
            let perpendicular = OriginalLounge.normalizedGround(.init(delta.x.addingProduct(-dot,movement.x),delta.z.addingProduct(-dot,movement.z)))
            // The source reuses this stack vector in the subsequent reaction
            // branch, including a degenerate zero perpendicular. Do not replace
            // it with the original center-to-center bearing afterward.
            reactionDelta=perpendicular
            let magnitude = (value.x*value.x).addingProduct(value.z,value.z).squareRoot()
            let amount = -magnitude*Float(0.05000000074505806)
            impulse.x = impulse.x.addingProduct(perpendicular.x,amount)
            impulse.z = impulse.z.addingProduct(perpendicular.z,amount)
        }
        return (value,opposed)
    }
    /// Source damping, gait projection, speed recovery and correction memory.
    /// Blocked actors still decay stored impulses, but do not receive a push.
    public mutating func integrate(_ contact: OriginalLounge.GroundPoint, opposed: Bool,
                                   forward: OriginalLounge.GroundPoint, stature: Float = 1,
                                   urgency: Float = 0, special: Bool = false,
                                   blocked: Bool = false) -> OriginalLounge.GroundPoint {
        let move = blocked ? OriginalLounge.GroundPoint(0,0):.init(contact.x+impulse.x,contact.z+impulse.z)
        impulse.x *= Float(0.9200000166893005); impulse.z *= Float(0.9200000166893005)
        if move.x == 0 && move.z == 0 { gait *= Float(0.8999999761581421) }
        else {
            let projected = (move.x*forward.x).addingProduct(move.z,forward.z)/max(0.001,stature)
            gait = gait.addingProduct(projected-gait,0.1)
        }
        let obstructed = opposed && !blocked
        let goal: Float = obstructed ? 0.029999999329447746:1
        let gain: Float = obstructed && !special ? Float(0.029999999329447746).addingProduct(-0.029999999329447746,urgency):0.029999999329447746
        speedScale = speedScale.addingProduct(goal-speedScale,gain)
        previous.x = previous.x.addingProduct(move.x-previous.x,0.1)
        previous.z = previous.z.addingProduct(move.z-previous.z,0.1)
        return move
    }
}

extension OriginalLounge {
    static func normalizedGround(_ point: GroundPoint) -> GroundPoint {
        let length = (point.x*point.x).addingProduct(point.z,point.z).squareRoot()
        return length > 0 ? .init(point.x/length,point.z/length):.init(0,0)
    }
    /// Predict the next tenth-of-a-cycle to stop near a foot plant, 02184cfc.
    public static func walkStopRadius(frame: Float, length: Float) -> Float {
        guard length > 0 else { return 2 }
        var predicted = frame.addingProduct(length,0.1)
        if predicted > length { predicted -= length }
        let quarter: Float = length*0.5-predicted < 0 ? 0.75:0.25
        let phase = abs(predicted.addingProduct(-length,quarter))/(length*0.25)
        return Float(2).addingProduct(4,phase*phase)
    }
}
