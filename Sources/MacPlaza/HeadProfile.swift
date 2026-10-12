import Foundation

struct HeadProfile {
    var width:CGFloat;var height:CGFloat;var roundness:CGFloat;var jaw:CGFloat
    init(_ w:CGFloat,_ h:CGFloat,_ r:CGFloat,_ j:CGFloat) {width=w;height=h;roundness=r;jaw=j}
    static let styles:[HeadProfile] = [
        .init(0.38,0.46,0.78,0.07),.init(0.36,0.47,0.88,0.12),.init(0.40,0.44,0.65,0.04),.init(0.40,0.44,0.48,0.02),
        .init(0.36,0.50,0.90,0.08),.init(0.39,0.47,0.72,0.04),.init(0.39,0.43,0.85,0.02),.init(0.41,0.46,0.58,0.05),
        .init(0.35,0.49,0.82,0.16),.init(0.36,0.47,0.95,0.18),.init(0.41,0.45,0.75,0.06),.init(0.38,0.48,0.62,0.08)
    ]
    func radius(at y:CGFloat) -> CGFloat {pow(sqrt(max(0,1-y*y)),roundness)*(1-jaw*pow(max(0,-y),0.65))}
}
