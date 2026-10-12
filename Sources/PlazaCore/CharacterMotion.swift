import Foundation

/// Foot-contact motion shared by the native resource-free rig. The bundled WebGL
/// adapter uses the same equations and dimensions in motion.js.
public struct CharacterMotion: Sendable {
    public struct Rotation: Sendable {public var x=0.0;public var y=0.0;public var z=0.0}
    public struct Foot: Sendable {public var z:Double;public var y:Double;public var pitch:Double;public var planted:Bool}
    public var bob:Double
    public var hop:Double
    public var arms:[Rotation]
    public var elbows:[Rotation]
    public var torso:Rotation
    public var head:Rotation
    public var wrist:Double
    public var legs:[[Double]]
    public var feet:[Foot]
    private static func clamp(_ v:Double,_ a:Double,_ b:Double)->Double{max(a,min(b,v))}
    public static func foot(phase:Double,amount:Double)->Foot {
        let u=(phase/(2 * .pi)).truncatingRemainder(dividingBy:1),t=u<0 ? u+1:u
        if t<0.6 {return Foot(z:(0.144-0.288*t/0.6)*amount,y:0,pitch:0,planted:true)}
        let f=(t-0.6)/0.4
        return Foot(z:(-0.144+0.288*f*f*(3-2*f))*amount,y:0.075*pow(sin(.pi*f),1.5)*amount,pitch:-0.25*sin(.pi*f)*amount,planted:false)
    }
    public static func leg(_ f:Foot,hipY:Double)->[Double] {
        let upper=0.34,lower=0.36,y=hipY-0.065-f.y,d=clamp(hypot(y,f.z),0.05,upper+lower-0.00001)
        let knee=Double.pi-acos(clamp((upper*upper+lower*lower-d*d)/(2*upper*lower),-1,1))
        let hip=atan2(-f.z,y)-acos(clamp((upper*upper+d*d-lower*lower)/(2*upper*d),-1,1))
        return [hip,knee,f.pitch-hip-knee]
    }
    public static func solve(state:Int,phase:Double,amount:Double,time:Double=0,social:Bool=false,lookYaw:Double=0,turn:Double=0)->CharacterMotion {
        let amount=clamp(amount,0,1),stride=sin(phase),a=time*3
        let feet=[foot(phase:phase,amount:amount),foot(phase:phase + .pi,amount:amount)]
        var bob = -0.001-0.018*amount*pow(cos(phase),2),hop=0.0
        for f in feet {bob=min(bob,0.065+f.y+sqrt(0.699*0.699-f.z*f.z)-0.764)}
        var la=Rotation(x:-stride*0.22*amount,z:-0.08),ra=Rotation(x:stride*0.22*amount,z:0.08)
        var le=Rotation(x:-0.045),re=le
        var torso=Rotation(x:0.025*amount,z:-stride*0.018*amount-clamp(turn,-3.5,3.5)*0.009*amount)
        var head=Rotation(x:-0.025*amount,y:lookYaw+sin(time*0.85)*0.025,z:-torso.z*0.5),wrist=0.0
        if state==0 {torso.z=sin(time*1.5)*0.006;head.x=sin(time*1.1)*0.015}
        if state==2 {torso.y=clamp(turn*0.025,-0.09,0.09);head.y+=clamp(turn*0.045,-0.16,0.16)}
        if state==3 {
            if social {ra.x = -0.42-0.12*sin(a);ra.z=0.18;re.x = -0.85-0.25*sin(a*0.7);head.x=sin(a*0.6)*0.035}
            else {ra.z=2+sin(a*2.8)*0.12;ra.x = -0.12;re.x = -0.25;wrist=sin(a*4.8)*0.32;head.z = -0.045}
        }
        if state==4 {
            let beat=(time.truncatingRemainder(dividingBy:1.05)+1.05).truncatingRemainder(dividingBy:1.05),flight=clamp((beat-0.18)/0.52,0,1)
            hop=time<0 ? 0:0.085*sin(.pi*flight);bob-=0.022*sin(.pi*clamp(beat/0.18,0,1))
            la.z = -2.35;ra.z=2.35;le.x = -0.16;re.x = -0.16;head.x = -0.07
        }
        if state==5 {
            if social {head.x=0.055+0.07*sin(a*0.75);la.x = -0.06;ra.x = -0.08}
            else {la.x = -0.24;ra.x = -0.24;le.x = -0.5;re.x = -0.5;la.z = -0.22;ra.z=0.22;head.x = -0.05}
        }
        return CharacterMotion(bob:bob,hop:hop,arms:[la,ra],elbows:[le,re],torso:torso,head:head,wrist:wrist,legs:feet.map{leg($0,hipY:0.764+bob)},feet:feet)
    }
}
