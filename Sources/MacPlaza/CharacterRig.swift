import SceneKit
import SwiftUI
import PlazaCore

@MainActor
final class CharacterRig {
    let root: SCNNode
    let body: SCNNode
    let torso:SCNNode
    let leftElbow=SCNNode(),rightElbow=SCNNode(),leftHand=SCNNode(),rightHand=SCNNode(),leftAnkle=SCNNode(),rightAnkle=SCNNode()
    private let contactShadow=SCNNode()
    let stature:CGFloat
    let head: SCNNode
    let leftArm: SCNNode
    let rightArm: SCNNode
    let leftLeg: SCNNode
    let rightLeg: SCNNode
    let leftKnee:SCNNode
    let rightKnee:SCNNode
    let face: SCNNode
    private let openFace: NSImage
    private let avatar: Avatar
    private var blinking = false
    private var mood:FaceMood = .neutral
    static let sphere: SCNGeometry = { let g=SCNSphere(radius:1); g.segmentCount=20; return g }()
    private static var materials: [String:SCNMaterial] = [:]
    static func material(_ color: NSColor) -> SCNMaterial {
        if let m=materials[color.description] { return m }; let m=SCNMaterial(); m.diffuse.contents=color; m.roughness.contents=0.85; m.lightingModel = .blinn; m.specular.contents=NSColor(white:0.16,alpha:1); materials[color.description]=m; return m }
    private static var sphereColors: [String:SCNGeometry] = [:]
    static func ellipsoid(_ scale: SCNVector3, _ color: NSColor, at p: SCNVector3 = SCNVector3Zero) -> SCNNode {
        let key=color.description; let g:SCNGeometry
        if let cached=sphereColors[key] { g=cached } else { g=sphere.copy() as! SCNGeometry; g.materials=[material(color)]; sphereColors[key]=g }; let n=SCNNode(geometry:g); n.scale=scale; n.position=p; return n
    }
    init(_ a: Avatar) {
        avatar=a; root=SCNNode(); body=SCNNode(); torso=SCNNode(); head=SCNNode(); leftArm=SCNNode(); rightArm=SCNNode(); leftLeg=SCNNode(); rightLeg=SCNNode(); leftKnee=SCNNode(); rightKnee=SCNNode()
        let f=a.features, skin=AvatarArtwork.skins[a.skin], outfit=AvatarArtwork.outfits[a.outfit]
        stature=CGFloat(0.72+a.height*0.40);let girth=CGFloat(0.76+a.build*0.48)
        root.addChildNode(body);body.position.y=0.844*stature;body.scale=SCNVector3(girth,stature,stature);body.addChildNode(torso)
        let shirt=Self.torsoMesh(female:f.gender==1);shirt.materials=[Self.material(outfit)]
        let clothing=SCNNode(geometry:shirt);clothing.scale.z=0.68*girth/stature;torso.addChildNode(clothing)
        torso.addChildNode(Self.ellipsoid(SCNVector3(0.067,0.085,0.067),skin,at:SCNVector3(0,0.59,0)))
        for (limb,elbow,hand,side) in [(leftArm,leftElbow,leftHand,CGFloat(-1)),(rightArm,rightElbow,rightHand,CGFloat(1))] {
            limb.position=SCNVector3(side*0.18,0.51,0);torso.addChildNode(limb)
            func sleeve(_ parent:SCNNode,_ top:CGFloat,_ bottom:CGFloat){let g=SCNCone(topRadius:top,bottomRadius:bottom,height:0.27);g.radialSegmentCount=12;g.materials=[Self.material(outfit)];let n=SCNNode(geometry:g);n.position.y = -0.135;parent.addChildNode(n)}
            sleeve(limb,0.054,0.047);elbow.position.y = -0.27;limb.addChildNode(elbow)
            elbow.addChildNode(Self.ellipsoid(SCNVector3(0.047,0.047,0.047),outfit));sleeve(elbow,0.047,0.040)
            hand.position.y = -0.285;elbow.addChildNode(hand);hand.addChildNode(Self.ellipsoid(SCNVector3(0.052,0.058,0.048),skin))
        }
        for (limb,knee,ankle,side) in [(leftLeg,leftKnee,leftAnkle,CGFloat(-1)),(rightLeg,rightKnee,rightAnkle,CGFloat(1))] {
            limb.position=SCNVector3(side*0.085,-0.08,0);body.addChildNode(limb)
            func segment(_ parent:SCNNode,_ top:CGFloat,_ bottom:CGFloat,_ length:CGFloat){let g=SCNCone(topRadius:top,bottomRadius:bottom,height:length);g.radialSegmentCount=12;g.materials=[Self.material(NSColor(hex:0x4B4C50))];let n=SCNNode(geometry:g);n.position.y = -length/2;parent.addChildNode(n)}
            segment(limb,0.050,0.043,0.34);knee.position.y = -0.34;limb.addChildNode(knee)
            knee.addChildNode(Self.ellipsoid(SCNVector3(0.043,0.043,0.043),NSColor(hex:0x4B4C50)));segment(knee,0.043,0.037,0.36)
            ankle.position.y = -0.36;knee.addChildNode(ankle)
            ankle.addChildNode(Self.ellipsoid(SCNVector3(0.058,0.055,0.10),NSColor(hex:0x3A3B3E),at:SCNVector3(0,-0.01,0.025)))
        }
        head.position=SCNVector3(0,1.454*stature+0.378,0);head.scale=SCNVector3(0.9,0.9,0.9);root.addChildNode(head)
        let profile=HeadProfile.styles[a.face],rx=profile.width,ry=profile.height,rz:CGFloat=0.34
        let skinMesh=Self.headMesh(rx:rx,ry:ry,rz:rz,profile:profile); skinMesh.materials=[Self.material(skin)]; head.addChildNode(SCNNode(geometry:skinMesh))
        for side in [-1 as CGFloat,1] { head.addChildNode(Self.ellipsoid(SCNVector3(0.052,0.085,0.045),skin,at:SCNVector3(side*rx,-0.02,0))) }
        openFace=AvatarArtwork.face(a)
        let patch=Self.faceMesh(rx:rx,ry:ry,rz:rz,profile:profile)
        let mask=SCNMaterial(); mask.diffuse.contents=openFace; mask.lightingModel = .constant; mask.isDoubleSided=false; mask.writesToDepthBuffer=false; mask.transparencyMode = .aOne
        patch.materials=[mask]; face=SCNNode(geometry:patch); face.renderingOrder=2; head.addChildNode(face)
        let ns=CGFloat(0.65+f.noseSize*0.8)
        if a.nose == 0 {
            let g=Self.noseWedge(size:ns);g.materials=[Self.material(skin)]
            let n=SCNNode(geometry:g);n.position=SCNVector3(0,CGFloat(-0.10-(f.noseY-0.5)*0.34-(a.featureHeight-0.5)*0.18),rz*0.98);head.addChildNode(n)
        } else if [1,6,9,11,12,13].contains(a.nose) {
            head.addChildNode(Self.ellipsoid(SCNVector3(0.007*ns,0.034*ns,0.018*ns),skin,at:SCNVector3(0,CGFloat(-0.10-(f.noseY-0.5)*0.34-(a.featureHeight-0.5)*0.18),rz*0.99)))
        }
        head.addChildNode(HairGeometry.node(a,rx:rx,ry:ry,rz:rz))
        // Merge stationary head parts by shared material, leaving the blinking face independent.
        face.removeFromParentNode()
        let merged=head.flattenedClone(); head.childNodes.forEach { $0.removeFromParentNode() }
        merged.position=SCNVector3Zero; head.addChildNode(merged); head.addChildNode(face)
        let shadow=SCNPlane(width:0.9,height:0.50); let sm=SCNMaterial(); sm.diffuse.contents=Self.shadowImage; sm.lightingModel = .constant; sm.writesToDepthBuffer=false; shadow.materials=[sm]
        contactShadow.geometry=shadow;contactShadow.eulerAngles.x = -.pi/2;contactShadow.position.y=0.005;root.addChildNode(contactShadow)
    }
    func pose(state:Int,phase:CGFloat,amount:CGFloat=1,delta:CGFloat=1,social:Bool=false,time:Double=0,lookYaw:Double=0,turn:Double=0) {
        let p=CharacterMotion.solve(state:state,phase:Double(phase),amount:Double(amount),time:time,social:social,lookYaw:lookYaw,turn:turn)
        contactShadow.position.y=0.005-root.position.y;body.position.y=(0.844+CGFloat(p.bob))*stature;head.position.y=(1.454+CGFloat(p.bob))*stature+0.378
        let blend:CGFloat=delta>=0.2 ? 1:1-exp(-delta*13)
        func apply(_ n:SCNNode,_ v:CharacterMotion.Rotation) {let old=n.eulerAngles;n.eulerAngles=SCNVector3(old.x+(CGFloat(v.x)-old.x)*blend,old.y+(CGFloat(v.y)-old.y)*blend,old.z+(CGFloat(v.z)-old.z)*blend)}
        apply(leftArm,p.arms[0]);apply(rightArm,p.arms[1]);apply(leftElbow,p.elbows[0]);apply(rightElbow,p.elbows[1]);apply(torso,p.torso);apply(head,p.head);rightHand.eulerAngles.z=CGFloat(p.wrist)
        for (i,leg,knee,ankle) in [(0,leftLeg,leftKnee,leftAnkle),(1,rightLeg,rightKnee,rightAnkle)] {leg.eulerAngles.x=CGFloat(p.legs[i][0]);knee.eulerAngles.x=CGFloat(p.legs[i][1]);ankle.eulerAngles.x=CGFloat(p.legs[i][2])}
    }
    private static func torsoMesh(female:Bool)->SCNGeometry {
        let rings:[(CGFloat,CGFloat)]=[(0,-0.085),(female ? 0.205:0.175,-0.08),(female ? 0.226:0.19,-0.05),(female ? 0.216:0.18,0.02),(0.158,0.22),(0.177,0.43),(0.195,0.51),(0.175,0.55),(0.09,0.58),(0,0.58)]
        let columns=20;var vertices:[SCNVector3]=[],normals:[SCNVector3]=[],indices:[Int32]=[]
        for i in rings.indices {
            let prev=rings[max(0,i-1)],next=rings[min(rings.count-1,i+1)],dy=next.1-prev.1,dr=next.0-prev.0,length=max(0.00001,hypot(dy,dr))
            for j in 0...columns {let angle=CGFloat(j)*2 * .pi/CGFloat(columns);vertices.append(SCNVector3(rings[i].0*sin(angle),rings[i].1,rings[i].0*cos(angle)));normals.append(SCNVector3(dy/length*sin(angle),-dr/length,dy/length*cos(angle)))}
        }
        for i in 0..<(rings.count-1){for j in 0..<columns{let a=Int32(i*(columns+1)+j),b=a+Int32(columns+1);indices += [a,a+1,b,a+1,b+1,b]}}
        return SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }
    func setFace(blink:Bool,mood:FaceMood) {
        guard blink != blinking || mood != self.mood else {return};blinking=blink;self.mood=mood
        face.geometry?.firstMaterial?.diffuse.contents=AvatarArtwork.face(avatar,blink:blink,mood:mood)
    }
    func setBlink(_ closed:Bool) {setFace(blink:closed,mood:mood)}
    static func addLighting(to scene: SCNScene) {
        let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity=520; ambient.light?.color=NSColor.white; scene.rootNode.addChildNode(ambient)
        let key=SCNNode(); key.light=SCNLight(); key.light?.type = .directional; key.light?.intensity=780; key.eulerAngles=SCNVector3(-0.7,-0.5,0); scene.rootNode.addChildNode(key)
    }
    private static let shadowImage: NSImage = NSImage(size:CGSize(width:64,height:64),flipped:false) { _ in
        guard let c=NSGraphicsContext.current?.cgContext, let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor.black.withAlphaComponent(0.14).cgColor,NSColor.clear.cgColor] as CFArray,locations:[0,1]) else { return false }
        c.drawRadialGradient(gradient,startCenter:CGPoint(x:32,y:32),startRadius:0,endCenter:CGPoint(x:32,y:32),endRadius:32,options:[]); return true
    }
    private static func headMesh(rx:CGFloat,ry:CGFloat,rz:CGFloat,profile:HeadProfile) -> SCNGeometry {
        var vertices:[SCNVector3]=[],normals:[SCNVector3]=[],indices:[Int32]=[]
        let cols=32,rows=24
        for y in 0...rows { for x in 0...cols {
            let t=CGFloat(y) * .pi/CGFloat(rows),p=CGFloat(x)*2 * .pi/CGFloat(cols),ny=cos(t),radial=profile.radius(at:ny)
            vertices.append(SCNVector3(rx*radial*cos(p),ry*ny,rz*sin(t)*sin(p)))
            normals.append(SCNVector3(sin(t)*cos(p),ny,sin(t)*sin(p)))
        }}
        for y in 0..<rows { for x in 0..<cols { let i=Int32(y*(cols+1)+x),n=Int32(cols+1); indices += [i,i+1,i+n,i+1,i+n+1,i+n] } }
        return SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }
    private static func faceMesh(rx: CGFloat, ry: CGFloat, rz: CGFloat, profile:HeadProfile) -> SCNGeometry {
        var vertices:[SCNVector3]=[], normals:[SCNVector3]=[],uv:[CGPoint]=[],indices:[Int32]=[]; let columns=24,rows=24
        for y in 0...rows { for x in 0...columns {
            let u=CGFloat(x)/CGFloat(columns),v=CGFloat(y)/CGFloat(rows),phi=(u-0.5)*2.3,theta=(v-0.5)*2.3
            let radial=profile.radius(at:-sin(theta))
            let p=SCNVector3(sin(phi)*radial*rx*1.006,-sin(theta)*ry*1.006,cos(phi)*cos(theta)*rz*1.009)
            vertices.append(p); normals.append(SCNVector3(p.x/rx,p.y/ry,p.z/rz)); uv.append(CGPoint(x:Double(u),y:Double(v)))
        }}
        for y in 0..<rows { for x in 0..<columns { let i=Int32(y*(columns+1)+x),n=Int32(columns+1); indices += [i,i+n,i+1,i+1,i+n,i+n+1] } }
        return SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uv)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }
    private static func noseWedge(size:CGFloat) -> SCNGeometry {
        let v=[SCNVector3(0,0.043*size,0),SCNVector3(-0.032*size,-0.022*size,0),SCNVector3(0.032*size,-0.022*size,0),SCNVector3(0,-0.018*size,0.065*size)]
        let indices:[Int32]=[0,1,3,0,3,2,1,2,3,0,2,1]
        return SCNGeometry(sources:[SCNGeometrySource(vertices:v)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }

}

struct LegacyCharacterPreview: NSViewRepresentable {
    let avatar: Avatar
    var angle: CGFloat = 0
    var pose: Int = 0
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let v=SCNView(); v.backgroundColor = .clear; v.antialiasingMode = .multisampling4X; v.preferredFramesPerSecond=30; v.rendersContinuously=false
        v.setAccessibilityElement(false); return v
    }
    func updateNSView(_ v: SCNView,context: Context) {
        let c=context.coordinator
        if c.avatar != avatar {
            c.avatar=avatar; let scene=SCNScene(),rig=CharacterRig(avatar); scene.rootNode.addChildNode(rig.root); CharacterRig.addLighting(to:scene)
            let camera=SCNNode(); camera.camera=SCNCamera(); camera.camera?.usesOrthographicProjection=true; camera.camera?.wantsHDR=false; camera.camera?.orthographicScale=1.38; camera.position=SCNVector3(0,1.20,5); scene.rootNode.addChildNode(camera)
            v.scene=scene; v.pointOfView=camera; c.rig=rig
        }
        c.rig?.root.eulerAngles.y=angle; c.rig?.pose(state:pose,phase:1,amount:pose==1 ? 1:0,time:0.4); c.rig?.setFace(blink:false,mood:pose==4 ? .happy:pose==5 ? .surprised:.neutral); v.needsDisplay=true
    }
    final class Coordinator { var avatar: Avatar?; var rig: CharacterRig? }
}
