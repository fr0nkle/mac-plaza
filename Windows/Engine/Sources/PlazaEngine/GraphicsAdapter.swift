import Foundation
import PlazaCore
typealias CGFloat = Double
struct CGPoint {var x:Double,y:Double;init(x:Double,y:Double){self.x=x;self.y=y}}
struct CGRect {var minX:Double,minY:Double,width:Double,height:Double;init(x:Double,y:Double,width:Double,height:Double){minX=x;minY=y;self.width=width;self.height=height}}
// Data-only host adapters for the unchanged Mac artwork algorithms.
struct NSColor {
    var r:Double,g:Double,b:Double,a:Double=1
    init(hex:Int){r=Double((hex>>16)&255)/255;g=Double((hex>>8)&255)/255;b=Double(hex&255)/255}
    init(_ r:Double,_ g:Double,_ b:Double,_ a:Double=1){self.r=r;self.g=g;self.b=b;self.a=a}
    static let white=NSColor(1,1,1),black=NSColor(0,0,0)
    var cgColor:NSColor{self};var css:String{"rgba(\(r*255),\(g*255),\(b*255),\(a))"};var json:[Double]{[r,g,b,a]}
    func withAlphaComponent(_ value:Double)->NSColor{NSColor(r,g,b,value)}
    func blended(withFraction t:Double,of other:NSColor)->NSColor?{NSColor(r*(1-t)+other.r*t,g*(1-t)+other.g*t,b*(1-t)+other.b*t,a*(1-t)+other.a*t)}
}
class CGPath {
    var commands:[[Any]]=[];init(){}
    init(roundedRect r:CGRect,cornerWidth:CGFloat,cornerHeight:CGFloat,transform:Any?){commands=[["roundRect",Double(r.minX),Double(r.minY),Double(r.width),Double(r.height),Double(cornerWidth),Double(cornerHeight)]]}
}
final class CGMutablePath:CGPath {
    func move(to p:CGPoint){commands.append(["moveTo",Double(p.x),Double(p.y)])}
    func addLine(to p:CGPoint){commands.append(["lineTo",Double(p.x),Double(p.y)])}
    func addQuadCurve(to p:CGPoint,control c:CGPoint){commands.append(["quadraticCurveTo",Double(c.x),Double(c.y),Double(p.x),Double(p.y)])}
    func addCurve(to p:CGPoint,control1 a:CGPoint,control2 b:CGPoint){commands.append(["bezierCurveTo",Double(a.x),Double(a.y),Double(b.x),Double(b.y),Double(p.x),Double(p.y)])}
    func addEllipse(in r:CGRect){commands.append(["ellipseRect",Double(r.minX),Double(r.minY),Double(r.width),Double(r.height)])}
    func addRoundedRect(in r:CGRect,cornerWidth:CGFloat,cornerHeight:CGFloat){commands.append(["roundRect",Double(r.minX),Double(r.minY),Double(r.width),Double(r.height),Double(cornerWidth),Double(cornerHeight)])}
    func addLines(between points:[CGPoint]){guard let first=points.first else{return};move(to:first);for p in points.dropFirst(){addLine(to:p)}}
    func closeSubpath(){commands.append(["closePath"])}
}
enum CGLineCap{case round,butt};enum CGLineJoin{case round}
final class CGContext {
    var commands:[[Any]]=[]
    func closePath(){commands.append(["closePath"])}
    func saveGState(){commands.append(["save"])};func restoreGState(){commands.append(["restore"])}
    func scaleBy(x:CGFloat,y:CGFloat){commands.append(["scale",Double(x),Double(y)])}
    func translateBy(x:CGFloat,y:CGFloat){commands.append(["translate",Double(x),Double(y)])}
    func rotate(by value:CGFloat){commands.append(["rotate",Double(value)])}
    func setLineCap(_ value:CGLineCap){commands.append(["lineCap",value == .round ? "round":"butt"])}
    func setLineJoin(_ value:CGLineJoin){commands.append(["lineJoin","round"])}
    func setLineWidth(_ value:CGFloat){commands.append(["lineWidth",Double(value)])}
    func setFillColor(_ value:NSColor){commands.append(["fillStyle",value.css])}
    func setStrokeColor(_ value:NSColor){commands.append(["strokeStyle",value.css])}
    func addPath(_ value:CGPath){commands.append(["path",value.commands])}
    func move(to p:CGPoint){commands.append(["moveTo",Double(p.x),Double(p.y)])}
    func addLine(to p:CGPoint){commands.append(["lineTo",Double(p.x),Double(p.y)])}
    func addQuadCurve(to p:CGPoint,control c:CGPoint){commands.append(["quadraticCurveTo",c.x,c.y,p.x,p.y])}
    func addCurve(to p:CGPoint,control1 a:CGPoint,control2 b:CGPoint){commands.append(["bezierCurveTo",a.x,a.y,b.x,b.y,p.x,p.y])}
    func addLines(between points:[CGPoint]){guard let first=points.first else{return};move(to:first);for p in points.dropFirst(){addLine(to:p)}}
    func addArc(center:CGPoint,radius:CGFloat,startAngle:CGFloat,endAngle:CGFloat,clockwise:Bool){commands.append(["arc",Double(center.x),Double(center.y),Double(radius),Double(startAngle),Double(endAngle),clockwise])}
    func strokePath(){commands.append(["strokePath"])};func fillPath(){commands.append(["fillPath"])};func clip(){commands.append(["clipPath"])}
    func fillEllipse(in r:CGRect){commands.append(["fillEllipse",Double(r.minX),Double(r.minY),Double(r.width),Double(r.height)])}
    func strokeEllipse(in r:CGRect){commands.append(["strokeEllipse",Double(r.minX),Double(r.minY),Double(r.width),Double(r.height)])}
    func fill(_ r:CGRect){commands.append(["fillRect",Double(r.minX),Double(r.minY),Double(r.width),Double(r.height)])}
}
struct SCNVector3 {var x:CGFloat=0,y:CGFloat=0,z:CGFloat=0;init(_ x:CGFloat=0,_ y:CGFloat=0,_ z:CGFloat=0){self.x=x;self.y=y;self.z=z};var json:[Double]{[Double(x),Double(y),Double(z)]}}
enum Primitive{case triangles}
final class SCNMaterial {
    var color=NSColor.white,isDoubleSided=false,face=false
    func copy()->Any{let other=SCNMaterial();other.color=color;other.isDoubleSided=isDoubleSided;other.face=face;return other}
    var json:[String:Any]{["color":color.json,"doubleSided":isDoubleSided,"face":face]}
}
struct SCNGeometrySource {
    let kind:String,values:[Double]
    init(vertices:[SCNVector3]){kind="position";values=vertices.flatMap(\.json)}
    init(normals:[SCNVector3]){kind="normal";values=normals.flatMap(\.json)}
    init(textureCoordinates:[CGPoint]){kind="uv";values=textureCoordinates.flatMap{[Double($0.x),Double($0.y)]}}
}
struct SCNGeometryElement {let values:[Int32];init(indices:[Int32],primitiveType:Primitive){values=indices}}
final class SCNGeometry {
    var sources:[SCNGeometrySource],elements:[SCNGeometryElement],materials:[SCNMaterial]=[],primitive:String?
    init(sources:[SCNGeometrySource]=[],elements:[SCNGeometryElement]=[]){self.sources=sources;self.elements=elements}
    var json:[String:Any]{var value:[String:Any]=["attributes":Dictionary(uniqueKeysWithValues:sources.map{($0.kind,$0.values)}),"indices":elements.flatMap(\.values),"materials":materials.map(\.json)];if let primitive{value["primitive"]=primitive};return value}
}
final class SCNNode {
    var geometry:SCNGeometry?,position=SCNVector3(),scale=SCNVector3(1,1,1),eulerAngles=SCNVector3(),children:[SCNNode]=[]
    init(geometry:SCNGeometry?=nil){self.geometry=geometry}
    func addChildNode(_ node:SCNNode){children.append(node)}
    var json:[String:Any]{var value:[String:Any]=["position":position.json,"scale":scale.json,"rotation":eulerAngles.json,"children":children.map(\.json)];if let geometry{value["geometry"]=geometry.json};return value}
}
