import Foundation

public enum CrowdActivity:Int,Sendable {
    case rest, wave, talk, listen, lookAround, scratch, yawn, sit, cheer, surprise, bow
}
/// Host durations derived from installed clip frames. The resource-free
/// recreation uses 30 frames/second; native port cadence is supplied separately.
public struct CrowdTiming:Sendable {
    public var clips:[String:Double]
    public init(clips:[String:Double]=[:]) {self.clips=clips}
    public func seconds(_ name:String,_ fallback:Double)->Double {
        guard let d=clips[name],d.isFinite,d>0,d<=120 else{return fallback};return d
    }
    public var wave:Double {seconds("Handwaving00_o",20/30)+seconds("Handwaving00_l",15/30)*2+seconds("Handwaving00_oe",25/30)}
    public var talk:Double {seconds("Talk00_l",130/30)}
    public var bow:Double {seconds("Bow00_o",2)}
    public func duration(_ activity:CrowdActivity)->Double {
        switch activity {
        case .wave:return wave
        case .talk,.listen:return talk
        case .lookAround:return seconds("LookAround00_o",4.8)
        case .scratch:return seconds("Scratch00_o",3)
        case .yawn:return seconds("Yawn00_o",160/30)
        case .sit:return seconds("SquatDown00_o",50/30)+seconds("SquatDown00_l",4)*2+seconds("SquatDown00_oe",50/30)
        case .cheer:return seconds("MessageHappy00_l",50/30)
        case .surprise:return seconds("MessageSurprise00_o",1.5)+seconds("MessageSurprise00_l",100/30)
        case .bow:return bow
        case .rest:return 0
        }
    }
}
