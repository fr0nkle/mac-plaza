import AppKit
import PlazaCore

enum FaceMood:Int { case neutral, happy, surprised, speaking }

/// Original vector contours with independently authored feature silhouettes.
@MainActor
enum FaceDrawing {
    enum EyeKind { case almond, arch, round, oval, dot, line, closed, half, squint }
    struct Eye {
        var kind:EyeKind; var width:CGFloat; var height:CGFloat; var tilt:CGFloat; var lash:Int; var lower:Bool
        init(_ k:EyeKind,_ w:CGFloat=1,_ h:CGFloat=1,_ t:CGFloat=0,_ lash:Int=0,_ lower:Bool=false) { kind=k;width=w;height=h;tilt=t;self.lash=lash;self.lower=lower }
    }
    static let eyes:[Eye] = [
        .init(.almond,1,1,0,1), .init(.half,0.7,0.8,-0.2,1), .init(.arch), .init(.round,0.9,1.4),
        .init(.arch,1,1.15,0,1), .init(.half,0.85,0.9,-0.35), .init(.almond,1,0.75,-0.2), .init(.oval,1,1.15),
        .init(.arch,0.8,1.2,0.4), .init(.half,1,0.8), .init(.round,1,1.3,0,3), .init(.arch,0.8,0.9,0.3),
        .init(.arch,1,0.9,-0.2), .init(.closed,0.75,0.6), .init(.line,0.95,0.6,0,2), .init(.oval,1.05,0.75),
        .init(.half,0.95,0.85,0.25), .init(.half,1,0.8,0,0,true), .init(.dot,0.55,0.8), .init(.round,0.9,1.15,0,1,true),
        .init(.arch,1,1,0,2), .init(.line,0.95,0.8,0,0,true), .init(.half,1.1,0.65,-0.2), .init(.closed,1,0.65,0,1),
        .init(.almond,1.05,0.65,-0.2,2), .init(.arch,1.1,0.8,0.2,1), .init(.line,1,0.6), .init(.almond,1.15,0.9,-0.3),
        .init(.arch,0.9,1.4,0,1), .init(.arch,0.95,1,0.15,2), .init(.half,1.05,0.75,-0.35,1), .init(.half,1.0,0.65,0.1),
        .init(.arch,0.85,1.05), .init(.arch,1,1.2,0.25), .init(.closed,0.9,0.65), .init(.almond,1.2,1.05,0,3),
        .init(.almond,1.3,0.4,-0.2), .init(.almond,1.15,0.9,-0.35), .init(.oval,1,0.9,0,0,true), .init(.oval,1.1,0.85,0.3),
        .init(.arch,1.1,0.9,0,3), .init(.half,0.75,0.65,-0.1,1), .init(.half,1.05,1,0,2), .init(.half,1.1,1.15,0,0,true),
        .init(.oval,1.05,0.75,-0.12), .init(.round,1,1.25,0,3,true), .init(.round,1.05,1.4,0,2), .init(.squint,0.9,1),
        .init(.arch,1.1,0.85,0,0,true), .init(.arch,1.1,0.9,-0.2), .init(.almond,1.25,0.55,0,0,true), .init(.half,1.15,1.05,0,0,true),
        .init(.oval,1.2,0.8), .init(.arch,1.1,1,0,1), .init(.arch,1.05,1.0,0,1,true), .init(.half,1.1,0.95,0.25,0,true),
        .init(.almond,1.05,1.1,0,0,true), .init(.arch,1,0.85,0,0,true), .init(.arch,1.05,0.9,0,3), .init(.arch,1.05,1.15,0,2)
    ]
    static let ink=NSColor(hex:0x211D1B)
    static func eye(_ c:CGContext,id:Int,size:CGFloat,stretch:CGFloat,side:CGFloat,color:NSColor,blink:Bool,mood:FaceMood) {
        let s=eyes[id],w=(10+size*12)*s.width,h=(8+stretch*9)*s.height
        c.saveGState(); c.scaleBy(x:side,y:1); c.rotate(by:s.tilt)
        c.setStrokeColor(ink.cgColor); c.setFillColor(ink.cgColor); c.setLineWidth(1.7); c.setLineCap(.round)
        let p=CGMutablePath()
        if blink || mood == .happy || s.kind == .line || s.kind == .squint || s.kind == .closed {
            if s.kind == .squint && !blink && mood != .happy { p.move(to:CGPoint(x:w*0.35,y:-h*0.35));p.addLine(to:CGPoint(x:-w*0.35,y:0));p.addLine(to:CGPoint(x:w*0.35,y:h*0.35)) }
            else { p.move(to:CGPoint(x:-w/2,y:0));p.addQuadCurve(to:CGPoint(x:w/2,y:0),control:CGPoint(x:0,y:(blink || mood == .happy) ? -h*0.55:s.kind == .closed ? -h*0.65:0)) }
            c.addPath(p);c.strokePath()
            if s.lower { c.move(to:CGPoint(x:-w/2,y:h*0.35));c.addLine(to:CGPoint(x:w/2,y:h*0.35));c.strokePath() }
            c.restoreGState(); return
        }
        if s.kind == .dot {
            c.setFillColor(color.cgColor);c.fillEllipse(in:CGRect(x:-w*0.40,y:-h*0.4,width:w*0.8,height:h*0.8)); c.restoreGState();return
        }
        let hh=h*(mood == .surprised ? 1.25:1)
        switch s.kind {
        case .round,.oval: p.addEllipse(in:CGRect(x:-w/2,y:-hh/2,width:w,height:hh))
        case .half:
            p.move(to:CGPoint(x:-w/2,y:-hh*0.18));p.addLine(to:CGPoint(x:w/2,y:-hh*0.18));p.addCurve(to:CGPoint(x:-w/2,y:-hh*0.18),control1:CGPoint(x:w*0.45,y:hh*0.85),control2:CGPoint(x:-w*0.45,y:hh*0.85));p.closeSubpath()
        default:
            p.move(to:CGPoint(x:-w/2,y:hh*0.22));p.addCurve(to:CGPoint(x:w/2,y:hh*0.12),control1:CGPoint(x:-w*0.35,y:-hh*0.65),control2:CGPoint(x:w*0.30,y:-hh*0.70))
            p.addQuadCurve(to:CGPoint(x:-w/2,y:hh*0.22),control:CGPoint(x:0,y:s.kind == .arch ? hh*0.25:hh*0.63));p.closeSubpath()
        }
        c.addPath(p); c.setFillColor(NSColor(hex:0xFAFAF6).cgColor);c.fillPath()
        c.saveGState();c.addPath(p);c.clip()
        let irisWidth=min(w*0.59,hh*0.8),irisHeight=hh*0.96
        c.setFillColor(color.cgColor);c.fillEllipse(in:CGRect(x:-irisWidth/2,y:-irisHeight/2,width:irisWidth,height:irisHeight))
        c.setFillColor(ink.cgColor);c.fillEllipse(in:CGRect(x:-irisWidth*0.24,y:-irisHeight*0.32,width:irisWidth*0.48,height:irisHeight*0.64))
        c.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor);c.fillEllipse(in:CGRect(x:-irisWidth*0.25,y:-irisHeight*0.28,width:1.35,height:1.8));c.restoreGState()
        c.setStrokeColor(ink.cgColor)
        if s.kind == .arch {
            c.move(to:CGPoint(x:-w/2,y:hh*0.22));c.addCurve(to:CGPoint(x:w/2,y:hh*0.12),control1:CGPoint(x:-w*0.35,y:-hh*0.65),control2:CGPoint(x:w*0.30,y:-hh*0.70));c.strokePath()
        } else { c.addPath(p);c.strokePath() }
        for i in 0..<s.lash { let t=CGFloat(i);c.move(to:CGPoint(x:w*(0.35-t*0.05),y:-hh*(0.12+t*0.15)));c.addLine(to:CGPoint(x:w*(0.62-t*0.02),y:-hh*(0.25+t*0.28)));c.strokePath() }
        if s.lower { c.move(to:CGPoint(x:-w*0.4,y:hh*0.65));c.addQuadCurve(to:CGPoint(x:w*0.4,y:hh*0.65),control:CGPoint(x:0,y:hh*0.85));c.setLineWidth(1);c.strokePath() }
        c.restoreGState()
    }
    static func brow(_ c:CGContext,id:Int,size:CGFloat,stretch:CGFloat,side:CGFloat,color:NSColor,mood:FaceMood) {
        guard id != 23 else { return }
        c.saveGState();c.scaleBy(x:side,y:1); if mood == .surprised { c.translateBy(x:0,y:-3) }
        let w=10+size*15,h=1+stretch*5,p=CGMutablePath()
        c.setStrokeColor(color.cgColor);c.setFillColor(color.cgColor);c.setLineWidth(h*(id==0 || id==3 || id==7 || id==10 || id==19 ? 0.45:1));c.setLineCap(id==2 || id==4 || id==6 || id==12 || id==18 || id==21 ? .butt:.round)
        if id==16 {
            for i in 0..<5 { let x=CGFloat(i)/4*w-w/2,y = -sin(CGFloat(i) * .pi/4)*h;c.fillEllipse(in:CGRect(x:x-h/3,y:y-h/3,width:h*0.65,height:h*0.65)) };c.restoreGState();return
        }
        p.move(to:CGPoint(x:-w/2,y:1))
        switch id {
        case 2,10,14: p.addLine(to:CGPoint(x:w/2,y:id==10 ? -h:1))
        case 4,6,12,18:
            p.addLine(to:CGPoint(x:w*0.45,y:-h));p.addLine(to:CGPoint(x:w/2,y:h*0.5));p.addLine(to:CGPoint(x:-w/2,y:h));p.closeSubpath()
        case 5,21: p.addLine(to:CGPoint(x:0,y:-h*1.5));p.addLine(to:CGPoint(x:w/2,y:0))
        case 13: p.addQuadCurve(to:CGPoint(x:w/2,y:0),control:CGPoint(x:0,y:h*2))
        case 15,20,22: p.addCurve(to:CGPoint(x:w/2,y:1),control1:CGPoint(x:0,y:h*2),control2:CGPoint(x:w*0.05,y:-h*3))
        default: p.addCurve(to:CGPoint(x:w/2,y:1),control1:CGPoint(x:-w*0.1,y:-h*CGFloat(id==3 || id==17 ? 3:2)),control2:CGPoint(x:w*0.25,y:-h*CGFloat(id==8 ? 0:2)))
        }
        c.addPath(p);if [4,6,12,18].contains(id) {c.fillPath()}else{c.strokePath()};c.restoreGState()
    }
    static func nose(_ c:CGContext,id:Int,size:CGFloat,color:NSColor) {
        guard id != 0 else { return } // The first nose is a shaded 3D wedge.
        let w=4+size*8,h=4+size*10,p=CGMutablePath()
        c.setStrokeColor(color.blended(withFraction:0.32,of:ink)!.cgColor);c.setLineWidth(1.2);c.setLineCap(.round)
        if id==2 { c.setFillColor(color.blended(withFraction:0.35,of:ink)!.cgColor);for side in [-1 as CGFloat,1] {c.fillEllipse(in:CGRect(x:side*w*0.3-1,y:0,width:2,height:2.5))};return }
        switch id {
        case 1,6,9,11,12,13:
            p.move(to:CGPoint(x:id==13 ? -w*0.1:-w*0.15,y:-h*0.5));p.addQuadCurve(to:CGPoint(x:-w*0.3,y:h*0.35),control:CGPoint(x:-w*0.4,y:h*0.1));p.addQuadCurve(to:CGPoint(x:w*0.3,y:h*0.35),control:CGPoint(x:0,y:h*0.55));if [6,9,11].contains(id) {p.addLine(to:CGPoint(x:w*0.1,y:id==11 ? -h*0.5:0))}
        case 4: p.move(to:CGPoint(x:-w/2,y:1));p.addCurve(to:CGPoint(x:w/2,y:1),control1:CGPoint(x:-w/2,y:-h*0.7),control2:CGPoint(x:w/2,y:-h*0.7))
        case 8,17: p.move(to:CGPoint(x:-w*0.2,y:-h/2));p.addCurve(to:CGPoint(x:w*0.2,y:-h/2),control1:CGPoint(x:-w*0.8,y:h),control2:CGPoint(x:w*0.8,y:h))
        case 7,16:
            p.move(to:CGPoint(x:-w/2,y:-h*0.2));p.addCurve(to:CGPoint(x:0,y:h*0.4),control1:CGPoint(x:-w*0.7,y:h*0.5),control2:CGPoint(x:-w*0.2,y:h*0.1));p.addCurve(to:CGPoint(x:w/2,y:-h*0.2),control1:CGPoint(x:w*0.2,y:h*0.7),control2:CGPoint(x:w*0.8,y:h*0.3))
        default: p.move(to:CGPoint(x:-w/2,y:-h*0.1));p.addQuadCurve(to:CGPoint(x:w/2,y:-h*0.1),control:CGPoint(x:0,y:h*(id==10 ? 0.6:1.1)))
        }
        c.addPath(p);c.strokePath()
    }
    static func mouth(_ c:CGContext,id:Int,size:CGFloat,stretch:CGFloat,color:NSColor,mood:FaceMood) {
        let w=10+size*23,h=2+stretch*10,p=CGMutablePath()
        c.setStrokeColor(ink.cgColor);c.setLineWidth(1.1);c.setFillColor(color.cgColor)
        if mood == .happy || mood == .speaking || mood == .surprised {
            if mood == .surprised { c.setFillColor(ink.cgColor);c.fillEllipse(in:CGRect(x:-w*0.20,y:-h*0.3,width:w*0.4,height:h*1.2)) }
            else { p.move(to:CGPoint(x:-w*0.45,y:-h*0.15));p.addLine(to:CGPoint(x:w*0.45,y:-h*0.15));p.addQuadCurve(to:CGPoint(x:-w*0.45,y:-h*0.15),control:CGPoint(x:0,y:h*(mood == .speaking ? 1.2:0.9)));c.addPath(p);c.setFillColor(ink.cgColor);c.fillPath();c.setFillColor(NSColor.white.cgColor);c.fill(CGRect(x:-w*0.34,y:-h*0.08,width:w*0.68,height:h*0.25)) };return
        }
        func stroke(_ path:CGPath,_ width:CGFloat=1.4,_ tint:NSColor?=nil) {c.addPath(path);c.setStrokeColor((tint ?? ink).cgColor);c.setLineWidth(width);c.strokePath()}
        func filled(_ path:CGPath,_ tint:NSColor) {c.addPath(path);c.setFillColor(tint.cgColor);c.fillPath()}
        let lip=color,open=NSColor(hex:0x45241E)
        switch id {
        case 0,1,5,7,24,27:
            p.move(to:CGPoint(x:-w/2,y:0))
            p.addCurve(to:CGPoint(x:w/2,y:0),control1:CGPoint(x:-w*0.18,y:-h*(id==7 ? 1:0.55)),control2:CGPoint(x:w*0.18,y:-h*(id==1 ? -0.25:0.55)))
            p.addQuadCurve(to:CGPoint(x:-w/2,y:0),control:CGPoint(x:0,y:h*(id==7 ? 0.05:id==5 ? 0.30:0.9)));p.closeSubpath();filled(p,lip)
            let seam=CGMutablePath();seam.move(to:CGPoint(x:-w/2,y:0));seam.addQuadCurve(to:CGPoint(x:w/2,y:0),control:CGPoint(x:0,y:id==24 ? h*0.25:0));stroke(seam,0.8)
        case 2: c.setFillColor(lip.cgColor);c.fillEllipse(in:CGRect(x:-w*0.12,y:-h*0.4,width:w*0.24,height:h*0.85))
        case 4,13:
            p.addEllipse(in:CGRect(x:-w*(id==4 ? 0.28:0.48),y:-h*0.65,width:w*(id==4 ? 0.56:0.96),height:h*1.3));filled(p,open)
            c.saveGState();c.addPath(p);c.clip();c.setFillColor(lip.cgColor);c.fill(CGRect(x:-w/2,y:0,width:w,height:h));c.restoreGState()
        case 6,14,17,22,26,29,34:
            if id==26 {p.move(to:CGPoint(x:-w/2,y:0));p.addLines(between:[CGPoint(x:0,y:-h*0.7),CGPoint(x:w/2,y:0),CGPoint(x:0,y:h*0.7)]);p.closeSubpath()}
            else if id==34 {p.addRoundedRect(in:CGRect(x:-w/2,y:-h*0.55,width:w,height:h*1.1),cornerWidth:h*0.5,cornerHeight:h*0.5)}
            else {p.move(to:CGPoint(x:-w/2,y:-h*0.15));p.addQuadCurve(to:CGPoint(x:w/2,y:-h*0.15),control:CGPoint(x:0,y:id==6 ? -h*1.4:id==17 ? h*0.12:-h*0.12));p.addQuadCurve(to:CGPoint(x:-w/2,y:-h*0.15),control:CGPoint(x:0,y:h*(id==17 ? 0.6:1.35)));p.closeSubpath()}
            filled(p,open);stroke(p,1.8,lip)
            c.saveGState();c.addPath(p);c.clip();c.setFillColor(NSColor(hex:0xFFFDF4).cgColor)
            if id==14 || id==34 {c.fill(CGRect(x:-w/2,y:-h/2,width:w,height:h));c.setStrokeColor(lip.cgColor);c.setLineWidth(0.8);for i in -2...2 {c.move(to:CGPoint(x:CGFloat(i)*w/5,y:-h/2));c.addLine(to:CGPoint(x:CGFloat(i)*w/5,y:h/2));c.strokePath()}}
            else if id != 26 {c.fill(CGRect(x:-w/2,y:-h*0.45,width:w,height:h*0.38))};c.restoreGState()
        case 11: c.setFillColor(lip.cgColor);for y in [-h*0.6,h*0.12] {c.fillEllipse(in:CGRect(x:-w*0.45,y:y,width:w*0.9,height:h*0.48))}
        case 28: p.addRoundedRect(in:CGRect(x:-w*0.42,y:-h*0.15,width:w*0.84,height:h*0.40),cornerWidth:h*0.3,cornerHeight:h*0.3);filled(p,lip)
        case 8,10,12,18,35:
            p.move(to:CGPoint(x:-w/2,y:0));p.addCurve(to:CGPoint(x:0,y:id==12 ? -h*0.1:-h*0.35),control1:CGPoint(x:-w*0.28,y:h*0.4),control2:CGPoint(x:-w*0.20,y:-h*0.5));p.addCurve(to:CGPoint(x:w/2,y:0),control1:CGPoint(x:w*0.20,y:-h*0.5),control2:CGPoint(x:w*0.28,y:h*0.4));stroke(p,id==8 ? 1.7:1.3,lip)
        case 9: p.move(to:CGPoint(x:-w/2,y:-h*0.3));p.addLines(between:[CGPoint(x:0,y:h*0.3),CGPoint(x:w/2,y:-h*0.3)]);stroke(p,1.5,lip)
        case 15,20,31:
            p.move(to:CGPoint(x:-w/2,y:id==31 ? -h/2:0));p.addLine(to:CGPoint(x:-w*0.4,y:0));p.addLine(to:CGPoint(x:w*0.3,y:0));p.addLine(to:CGPoint(x:w/2,y:id==20 ? h*0.6:-h*0.3));stroke(p,1.4,lip)
        case 32:
            p.move(to:CGPoint(x:w*0.15,y:-h*0.6));p.addCurve(to:CGPoint(x:0,y:0),control1:CGPoint(x:-w*0.5,y:-h*0.8),control2:CGPoint(x:-w*0.4,y:0));p.addCurve(to:CGPoint(x:w*0.15,y:h*0.6),control1:CGPoint(x:-w*0.4,y:0),control2:CGPoint(x:-w*0.5,y:h*0.8));stroke(p,1.6,lip)
        default:
            let curve:CGFloat=[19,21,25,33].contains(id) ? h*0.8:id==30 ? -h*0.8:0
            p.move(to:CGPoint(x:-w/2,y:0));p.addQuadCurve(to:CGPoint(x:w/2,y:0),control:CGPoint(x:0,y:curve));stroke(p,1.3,id==19 || id==23 || id==30 ? ink:lip)
            if [3,16,21,25,33].contains(id) {for side in [-1 as CGFloat,1] {let q=CGMutablePath();q.move(to:CGPoint(x:side*w/2,y:-h*0.3));q.addQuadCurve(to:CGPoint(x:side*w/2,y:h*0.3),control:CGPoint(x:side*(w/2-1.5),y:0));stroke(q,1.1,lip)}}
            if id==33 {c.move(to:CGPoint(x:-w*0.15,y:h*0.75));c.addLine(to:CGPoint(x:w*0.15,y:h*0.75));c.strokePath()}
        }
    }
}
