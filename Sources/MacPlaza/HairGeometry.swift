import SceneKit
import PlazaCore

/// Authored silhouettes, indexed by the stored Wii U hairstyle ID.
/// These are original geometry descriptions, not console meshes or UI artwork.
@MainActor
enum HairGeometry {
    enum Fringe { case open, straight, teeth, side, centre, wisps, receding }
    enum Shape { case crop, bob, long, spikes, waves, curls, pony, twins, bun, cap, horseshoe, bald }
    struct Style {
        var shape:Shape; var fringe:Fringe; var length:CGFloat; var volume:CGFloat; var part:CGFloat; var detail:Int
        init(_ shape:Shape,_ fringe:Fringe = .open,_ length:CGFloat = 0,_ volume:CGFloat = 0,_ part:CGFloat = 0.5,_ detail:Int = 0) { self.shape=shape; self.fringe=fringe; self.length=length; self.volume=volume; self.part=part; self.detail=detail }
    }
    static let styles:[Style] = [
        .init(.long,.side,0.30,0.03), .init(.spikes,.side,0,0.12), .init(.pony,.centre,0.15,0,0.5,1), .init(.long,.centre,0.25),
        .init(.long,.straight,0.40), .init(.crop,.side,0.06,0.02), .init(.bob,.open,0.16), .init(.waves,.centre,0.30,0.06),
        .init(.long,.centre,0.30,0.03,0.5,1), .init(.pony,.centre,0.24), .init(.bob,.centre,0.18), .init(.bob,.teeth,0.16),
        .init(.bob,.side,0.18,0.02,0.3), .init(.crop,.teeth), .init(.bob,.side,0.20), .init(.waves,.centre,0.38,0.02),
        .init(.bob,.side,0.14), .init(.bob,.straight,0.21,0,0.5,1), .init(.bun,.open,0), .init(.long,.side,0.24,0.01,0.3,1),
        .init(.bob,.straight,0.16), .init(.bob,.straight,0.12,0.04), .init(.long,.centre,0.27,0,0.5,1), .init(.crop,.receding,0,-0.015),
        .init(.long,.straight,0.30,0,0.5,1), .init(.bob,.straight,0.22), .init(.pony,.teeth,0.05,0,0.7,1), .init(.long,.centre,0.30,0.05),
        .init(.twins,.centre,0.18,0,0.5,1), .init(.long,.centre,0.38,0), .init(.bald), .init(.spikes,.receding,0,0.10,0.5,1),
        .init(.long,.teeth,0.27,0), .init(.crop,.teeth,0,0.015), .init(.cap,.straight,0,0.025,0.5,1), .init(.crop,.straight,0.04,0.04),
        .init(.crop,.open,0,0), .init(.crop,.teeth,0,0.03), .init(.spikes,.open,0,0.14), .init(.crop,.open,0,0.035,0.5,2),
        .init(.crop,.teeth,0,0.005), .init(.horseshoe,.receding,0,-0.02,0.5,1), .init(.waves,.centre,0.27,0.07,0.5,2), .init(.spikes,.side,0,0.11,0.2,2),
        .init(.crop,.centre,0,0.02), .init(.crop,.open,0,-0.005), .init(.waves,.side,0,0.06), .init(.crop,.teeth,0,0.02),
        .init(.crop,.centre,0,0,0.3), .init(.crop,.open,0,0.065,0.5,2), .init(.long,.centre,0.16,0.03,0.5,1), .init(.crop,.wisps,0,0.015),
        .init(.crop,.wisps,0,0.025,0.5,1), .init(.waves,.side,0.20,0.015), .init(.bob,.centre,0.03,0.07), .init(.crop,.side,0,0.015,0.25),
        .init(.crop,.teeth,0,0.045,0.5,2), .init(.cap,.open,0,0.05), .init(.long,.open,0.29,0.01), .init(.crop,.receding,0,0.005),
        .init(.long,.centre,0.30,0.01,0.5,2), .init(.bob,.open,0.22,0), .init(.crop,.side,0.02,0.03,0.2,1), .init(.long,.wisps,0.24,0,0.5,1),
        .init(.waves,.open,0,0.05), .init(.horseshoe,.receding,0,-0.03), .init(.crop,.centre,0,0.015,0.5,1), .init(.crop,.receding,0,0.01,0.5,2),
        .init(.curls,.open,0,0.02), .init(.crop,.centre,0.06,0.035), .init(.crop,.side,0.04,0.025,0.3), .init(.waves,.centre,0.25,0.03),
        .init(.long,.straight,0.29,0.025), .init(.spikes,.side,0.12,0.09), .init(.crop,.side,0.06,0.025), .init(.spikes,.teeth,0.10,0.11),
        .init(.curls,.open,0,0.025), .init(.bob,.side,0.13,0), .init(.waves,.side,0.02,0.06,0.3,1), .init(.spikes,.straight,0,0.09),
        .init(.waves,.receding,0.23,0.01), .init(.bob,.centre,0.14,0.01,0.5,1), .init(.long,.open,0.32,0.025), .init(.curls,.open,0.08,0.045),
        .init(.pony,.side,0.18,0,0.3,2), .init(.waves,.side,0.29,0.02), .init(.crop,.receding,0,-0.015,0.5,2), .init(.waves,.side,0.12,0.04),
        .init(.horseshoe,.receding,0.02,-0.025), .init(.waves,.receding,0.15,0.02), .init(.long,.teeth,0.34,0.025), .init(.spikes,.straight,0,0.12),
        .init(.cap,.straight,0,0.015), .init(.long,.side,0.39,0), .init(.bob,.teeth,0.17,0.025), .init(.bob,.centre,0.19,0.01,0.5,1),
        .init(.curls,.open,0.30,0.03), .init(.pony,.open,0.24,0,0.5,1), .init(.bob,.wisps,0.24,0,0.5,1), .init(.crop,.wisps,0.06,0),
        .init(.bob,.straight,0.19,0.035), .init(.waves,.wisps,0.27,0.02), .init(.waves,.teeth,0.25,0.03), .init(.bun,.side,0,0.01),
        .init(.long,.straight,0.26,0,0.5,1), .init(.bob,.side,0.22,0.02,0.3), .init(.bob,.side,0.24,0.03,0.7), .init(.crop,.teeth,0,0.035,0.3,1),
        .init(.bob,.centre,0.18,0.015,0.5,2), .init(.pony,.side,0.03,0.02,0.3,1), .init(.long,.teeth,0.36,0.03), .init(.twins,.straight,0.18,0,0.5,1),
        .init(.spikes,.straight,0.10,0.08), .init(.crop,.straight,0,0.035), .init(.horseshoe,.receding,0,0.02), .init(.crop,.teeth,0,0.025,0.5,1),
        .init(.bob,.side,0.24,0.03,0.2), .init(.long,.open,0.30,0.01,0.5,1), .init(.bob,.open,0.20,0.01), .init(.curls,.straight,0,0.035),
        .init(.long,.teeth,0.27,0.02,0.5,2), .init(.spikes,.teeth,0,0.08,0.5,1), .init(.crop,.straight,0,0.035,0.5,1), .init(.long,.side,0.31,0.015,0.25),
        .init(.bob,.straight,0.21,0.02), .init(.spikes,.centre,0.16,0.10), .init(.twins,.teeth,0.04,0.01), .init(.curls,.open,0,0.055),
        .init(.long,.side,0.32,0.02,0.2), .init(.long,.straight,0.32,0.025), .init(.pony,.open,0.31,0.02,0.7,2), .init(.waves,.centre,0.32,0.04,0.5,1)
    ]
    // Stored IDs in Wii U maker display order; the values describe format/UI ordering.
    static let displayOrder:[Int] = [33, 47, 40, 37, 32, 107, 48, 51, 55, 70, 44, 66, 52, 50, 38, 49, 43, 31, 56, 68, 62, 115, 76, 119, 64, 81, 116, 121, 22, 58, 60, 87, 125, 117, 73, 75, 42, 89, 57, 54, 80, 34, 23, 86, 88, 118, 39, 36, 45, 67, 59, 65, 41, 30, 12, 16, 10, 82, 128, 129, 14, 95, 105, 100, 6, 20, 93, 102, 27, 4, 17, 110, 123, 8, 106, 72, 3, 21, 0, 98, 63, 90, 11, 120, 5, 74, 108, 94, 124, 25, 99, 69, 35, 13, 122, 113, 53, 24, 85, 83, 71, 131, 96, 101, 29, 7, 15, 112, 79, 1, 109, 127, 91, 26, 61, 103, 2, 77, 18, 92, 84, 9, 19, 130, 97, 104, 46, 78, 28, 114, 126, 111]
    private static var cache:[String:SCNGeometry]=[:]
    static func node(_ a:Avatar,rx:CGFloat,ry:CGFloat,rz:CGFloat) -> SCNNode {
        let s=styles[a.hair],root=SCNNode(),color=AvatarArtwork.hairs[a.hairColor]
        guard s.shape != .bald else { return root }
        let key="\(a.hair)-\(a.face)-\(a.hairColor)-\(a.features.flipHair)"
        let mesh:SCNGeometry
        if let g=cache[key] { mesh=g } else {
            mesh=scalp(s,rx:rx,ry:ry,rz:rz,roundness:HeadProfile.styles[a.face].roundness,flip:a.features.flipHair); let m=CharacterRig.material(color).copy() as! SCNMaterial;m.isDoubleSided=true;mesh.materials=[m]
            if cache.count>256 { cache.removeAll() }; cache[key]=mesh
        }
        root.addChildNode(SCNNode(geometry:mesh))
        let sign:CGFloat=a.features.flipHair ? -1:1
        if s.shape == .spikes {
            for i in 0..<7 {
                let x=CGFloat(i-3)*0.085,tip=CGFloat(0.075)+s.volume*0.35+CGFloat(i%2)*0.025
                let vertices=[SCNVector3(-0.075,-0.045,-0.035),SCNVector3(0.075,-0.045,-0.035),SCNVector3(0,-0.035,0.060),SCNVector3(0.045*sign,tip,-0.005)]
                let g=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],elements:[SCNGeometryElement(indices:[Int32(0),1,3,1,2,3,2,0,3,0,2,1],primitiveType:.triangles)])
                g.materials=[CharacterRig.material(color)];let n=SCNNode(geometry:g);n.position=SCNVector3(x,ry*0.90-abs(x)*0.3,0.08+CGFloat(i%2)*0.035);n.eulerAngles.z = -x*0.8;root.addChildNode(n)
            }
        }
        if s.shape == .pony || s.shape == .twins || s.shape == .bun {
            let sides:[CGFloat]=s.shape == .twins ? [-1,1]:[s.detail>0 ? sign:0]
            for side in sides {
                let bun=s.shape == .bun, high=s.detail==2 || bun
                let n=CharacterRig.ellipsoid(SCNVector3(bun ? 0.14:0.10,bun ? 0.13:0.14+s.length*0.55,bun ? 0.13:0.11),color,at:SCNVector3(side*(s.shape == .twins ? rx*0.95:rx*0.68),high ? ry*0.89:-0.08,-rz*(side==0 ? 1:0.75)))
                n.eulerAngles.z = -side*0.35; root.addChildNode(n)
                if !bun { root.addChildNode(CharacterRig.ellipsoid(SCNVector3(0.065,0.05,0.065),color,at:SCNVector3(side*rx*0.82,high ? ry*0.56:-0.03,-rz*0.72))) }
            }
        }
        return root
    }
    private static func scalp(_ s:Style,rx:CGFloat,ry:CGFloat,rz:CGFloat,roundness:CGFloat,flip:Bool) -> SCNGeometry {
        var vertices:[SCNVector3]=[],normals:[SCNVector3]=[],indices:[Int32]=[]
        let cols=64,rows=20,sign:CGFloat=flip ? -1:1
        let long=s.length>0.10 && s.shape != .pony && s.shape != .twins
        for y in 0...rows { for x in 0...cols {
            let p=CGFloat(x)*2 * .pi/CGFloat(cols),front=max(0,sin(p)),side=cos(p)*sign
            let teeth=(1+(2 / .pi)*asin(sin((p - .pi/2)*CGFloat(9+s.detail*2))))/2
            var fringe:CGFloat=0.92
            switch s.fringe {
            case .open: fringe=0.89
            case .straight: fringe=1.24
            case .teeth: fringe=1.02+teeth*(s.detail==1 ? 0.20:0.29)
            case .side: fringe=1.05+side*(0.36+(s.part-0.5)*0.4)+0.06*sin(p*3)
            case .centre: fringe=0.73+pow(abs(side),0.65)*0.79
            case .wisps: fringe=0.94+teeth*0.15+side*0.18
            case .receding: fringe=0.46+abs(side)*0.22
            }
            let rear:CGFloat=long ? 2.16+s.length*2:s.shape == .crop || s.shape == .spikes ? 1.75:1.98
            let u=min(1,max(0,(front-0.08)/0.47)),frontWeight=u*u*(3-2*u)
            let rounded:CGFloat=s.shape == .bob ? 0.34:s.shape == .long && s.fringe != .straight ? 0.15:0
            let end=(rear-rounded*pow(abs(cos(p)),3))*(1-frontWeight)+fringe*frontWeight
            let start:CGFloat=s.shape == .horseshoe ? 1.05:0
            let t=start+CGFloat(y)/CGFloat(rows)*(max(start+0.04,end)-start)
            let wave:CGFloat=(s.shape == .waves || s.shape == .curls) ? sin(p*CGFloat(s.shape == .curls ? 13:7)+t*4)*(s.shape == .curls ? 0.026:0.018):0
            let spike:CGFloat=0
            let volume:CGFloat=s.shape == .spikes ? 0.015:s.volume
            let lower=max(0,t - .pi/2)
            let radius:CGFloat=long && t > .pi/2 ? 1-(s.shape == .bob ? 0.14:0.04)*lower*lower:pow(sin(t),roundness)
            let width=rx+0.012+volume+wave+spike,depth=rz+0.016+volume*0.5+wave+spike
            var yy=ry*cos(t)+volume*0.6+spike
            if long && t > .pi/2 { yy = -ry*(t - .pi/2)*0.92; if s.detail>0 { yy += sin(p*7)*0.025*CGFloat(s.detail) } }
            if s.detail==2 && s.shape == .crop { yy=min(yy,ry*0.96+s.volume) }
            vertices.append(SCNVector3(width*radius*cos(p),yy,depth*radius*sin(p)))
            normals.append(SCNVector3(sin(t)*cos(p),long && t > .pi/2 ? -0.08:cos(t),sin(t)*sin(p)))
        }}
        for y in 0..<rows { for x in 0..<cols { if s.shape == .horseshoe && sin((CGFloat(x)+0.5)*2 * .pi/CGFloat(cols))>0.35 {continue}; let i=Int32(y*(cols+1)+x),n=Int32(cols+1); indices += [i,i+1,i+n,i+1,i+n+1,i+n] } }
        return SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    }
}
