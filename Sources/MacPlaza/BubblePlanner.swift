import Foundation

/// Reserve whole control rectangles, including labels, before placing journal cards.
/// Cards may be omitted on a small viewport; they never cover a launch target.
enum BubblePlanner {
    static func positions(size: CGSize, islands: [CGPoint], limit: Int = 3) -> [CGPoint] {
        let width=min(240,size.width*0.22),height:CGFloat=108
        guard size.width>400,size.height>320 else { return [] }
        let controls=islands.map { PlazaLayout.controlRect(at:$0,in:size).insetBy(dx:-10,dy:-10) }
        let preferred=[CGPoint(x:0.50,y:0.40),CGPoint(x:0.36,y:0.36),CGPoint(x:0.66,y:0.43),CGPoint(x:0.48,y:0.65),CGPoint(x:0.5,y:0.30),CGPoint(x:0.30,y:0.62),CGPoint(x:0.72,y:0.66)]
        var candidates=preferred
        for y in stride(from:0.27,through:0.78,by:0.08) { for x in stride(from:0.25,through:0.76,by:0.08) { candidates.append(CGPoint(x:x,y:y)) } }
        var reserved:[CGRect]=[],points:[CGPoint]=[]
        for p in candidates {
            let center=CGPoint(x:p.x*size.width,y:p.y*size.height)
            let rect=CGRect(x:center.x-width/2,y:center.y-height/2,width:width,height:height)
            guard rect.minY>24,rect.maxY<size.height-34,!controls.contains(where:{$0.intersects(rect)}),!reserved.contains(where:{$0.intersects(rect)}) else { continue }
            points.append(center); reserved.append(rect.insetBy(dx:-8,dy:-8))
            if points.count>=limit { break }
        }
        return points
    }
}
