import Foundation

/// Host choreography inspired by the plaza's running entrance. The installed
/// menu resource supplies Run00_l; these screen paths and timings are native.
public enum PlazaEntrance {
    public static let duration=7.2
    public static func delay(index:Int)->Double {Double((index*37)%101)/100*1.65}
    public static func arrivalTime(index:Int,goal:CrowdPoint)->Double {
        delay(index:index)+3.0+goal.y*1.8
    }
    public static func progress(index:Int,goal:CrowdPoint,elapsed:Double)->Double {
        min(1,max(0,(elapsed-delay(index:index))/(3.0+goal.y*1.8)))
    }
    public static func position(index:Int,goal:CrowdPoint,elapsed:Double)->CrowdPoint {
        let t=progress(index:index,goal:goal,elapsed:elapsed)
        // A wide, staggered stream fans out from above the visible plaza.
        // Ease only near arrival; most of the route keeps a running pace.
        let u=(t-0.8)/0.2
        let eased=t<0.8 ? t:(0.8+0.2*(u+u*u-u*u*u))
        let startX=min(0.95,max(0.05,goal.x+sin(Double(index)*2.399)*0.16))
        return CrowdPoint(startX+(goal.x-startX)*eased+sin(t * .pi)*sin(Double(index)*1.7)*0.035,
                          -0.16+(goal.y+0.16)*eased)
    }
    public static func iconDelay(at point:CrowdPoint)->Double {
        // Clockwise around the oval, starting with the upper left arc.
        let angle=atan2(point.y-0.44,point.x-0.5)
        let turn=(angle+Double.pi*0.75+Double.pi*2).truncatingRemainder(dividingBy:Double.pi*2)
        return 0.35+turn/(Double.pi*2)*1.25
    }
    public static func iconProgress(at point:CrowdPoint,elapsed:Double)->Double {
        min(1,max(0,(elapsed-iconDelay(at:point))/0.8))
    }
    public static func iconScale(progress:Double)->Double {
        guard progress>0 else{return 0.02}
        guard progress<1 else{return 1}
        return 1-pow(1-progress,3)+sin(progress * .pi)*0.19
    }
}
