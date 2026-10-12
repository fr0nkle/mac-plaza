import SceneKit
import SwiftUI
import PlazaCore

enum PlazaLayout {
    // Icon centers follow the reference's staggered oval, leaving space below
    // each icon for visitors and an open walkway through the middle.
    static let worldWidth = 48.0
    static let compactSlots: [CGPoint] = [
        CGPoint(x: 0.22, y: 0.18), CGPoint(x: 0.40, y: 0.105), CGPoint(x: 0.60, y: 0.105), CGPoint(x: 0.78, y: 0.18),
        CGPoint(x: 0.84, y: 0.55), CGPoint(x: 0.625, y: 0.67), CGPoint(x: 0.38, y: 0.65), CGPoint(x: 0.165, y: 0.55),
        CGPoint(x: 0.945, y: 0.33), CGPoint(x: 0.055, y: 0.33),
    ]
    static let expandedSlots: [CGPoint] = [
        CGPoint(x: 0.22, y: 0.18), CGPoint(x: 0.40, y: 0.105), CGPoint(x: 0.60, y: 0.105), CGPoint(x: 0.78, y: 0.18),
        CGPoint(x: 0.945, y: 0.33), CGPoint(x: 0.055, y: 0.33),
        CGPoint(x: 0.83, y: 0.68), CGPoint(x: 0.61, y: 0.72), CGPoint(x: 0.39, y: 0.72), CGPoint(x: 0.17, y: 0.68),
        CGPoint(x: 0.94, y: 0.52), CGPoint(x: 0.06, y: 0.52)
    ]
    static func slots(for count: Int) -> [CGPoint] { count > 10 ? expandedSlots : compactSlots }
    static func tileSize(in size: CGSize) -> CGFloat { max(80, min(136, size.width * 0.105, size.height * 0.19)) }
    static func controlRect(at point: CGPoint, in size: CGSize) -> CGRect {
        let tile = tileSize(in: size)
        return CGRect(x: point.x * size.width - max(tile / 2 + 8, 77), y: point.y * size.height - tile / 2 - 10,
                      width: max(tile + 16, 154), height: tile + 42)
    }
    static func bubblePositions(appCount: Int) -> [CGPoint] {
        appCount > 8 ? [CGPoint(x: 0.50, y: 0.36)] : [CGPoint(x: 0.37, y: 0.37), CGPoint(x: 0.65, y: 0.43), CGPoint(x: 0.48, y: 0.63)]
    }
}

@MainActor
final class PlazaEntranceClock: ObservableObject {
    @Published private(set) var anchor:Date?
    @Published private(set) var finished=false
    private var frozen=0.0
    func elapsed(at date:Date)->Double {finished ? PlazaEntrance.duration:anchor.map {max(0,date.timeIntervalSince($0))} ?? frozen}
    func resume(at elapsed:Double) {if !finished && anchor == nil {anchor=Date().addingTimeInterval(-elapsed)}}
    func pause() {if let anchor {frozen=max(0,Date().timeIntervalSince(anchor));self.anchor=nil}}
    func finish() {finished=true;anchor=nil;frozen=PlazaEntrance.duration}
}

@MainActor
final class PlazaArrivalClock: ObservableObject {
    @Published private(set) var avatar:Avatar?
    private(set) var anchor:Date?
    @Published private(set) var presentationTime=0.0
    func begin(_ avatar:Avatar) {self.avatar=avatar;anchor=nil;presentationTime=0}
    func elapsed(at date:Date)->Double? {avatar == nil ? nil:presentationTime}
    func resume(at elapsed:Double) {if avatar != nil && anchor == nil {anchor=Date().addingTimeInterval(-elapsed)}}
    func advance(to elapsed:Double) {
        guard avatar != nil,elapsed.isFinite else{return}
        presentationTime=min(PlazaArrival.duration,max(0,elapsed))
    }
    func pause() {anchor=nil}
    func finish() {
        guard avatar != nil else{return}
        avatar=nil;anchor=nil;presentationTime=0
    }
}

@MainActor
final class PlazaScene {
    let entranceClock=PlazaEntranceClock()
    let arrivalClock=PlazaArrivalClock()
    var onArrivalCue:((PlazaArrival.Cue)->Void)?
    var onArrivalStopped:(()->Void)?
    private var arrivalCues=Set<PlazaArrival.Cue>()
    func beginArrival(for id:UUID,animated:Bool) {
        guard let index=characters.firstIndex(where:{$0.id==id}) else{return}
        finishEntrance()
        onArrivalStopped?();arrivalCues=[]
        simulation.beginArrival(index:index)
        if animated {arrivalClock.begin(characters[index])}
        else {simulation.finishArrival();arrivalClock.finish()}
        apply()
    }
    func finishArrival() {simulation.finishArrival();arrivalClock.finish();arrivalCues=[];onArrivalStopped?();apply()}
    private var entrancePrepared=false
    private var rendererReady=false
    func beginEntrance(enabled:Bool) {
        guard !entrancePrepared else{return};entrancePrepared=true
        if enabled && !simulation.walkers.isEmpty {simulation.beginEntrance();apply()}
        else {finishEntrance()}
    }
    func finishEntrance() {simulation.finishEntrance();entranceClock.finish();apply()}
    func rendererDidBecomeReady() {rendererReady=true;apply()}
    let world=SCNScene()
    let camera=SCNNode()
    private var rigs:[CharacterRig]=[]
    private var characters:[Avatar]=[]
    private(set) var fflCharacters:[Avatar]=[]
    var fflFrame: (([[Double]])->Void)?
    var fflConfigure: (([Avatar])->Void)?
    private var fflOwner:UUID?
    var fflNoteTargets: (([Int]) -> Void)?
    private var notesOwner: UUID?
    private var noteTargets: [UUID] = []
    private var notePositions: (([UUID: CGPoint]) -> Void)?
    var noteIndices: [Int] { noteTargets.compactMap { id in characters.firstIndex(where: { $0.id == id }) } }
    func attachNotes(owner: UUID, targets: [UUID], positions: @escaping ([UUID: CGPoint]) -> Void) {
        notesOwner = owner; notePositions = positions
        if noteTargets != targets { noteTargets = Array(targets.prefix(6)); fflNoteTargets?(noteIndices) }
        if fflOwner == nil { emitLegacyAnchors() }
    }
    func detachNotes(owner: UUID) {
        guard notesOwner == owner else { return }
        notesOwner = nil; noteTargets = []; notePositions = nil; fflNoteTargets?([])
    }
    func acceptFFLAnchors(_ values: [[Double]]) {
        var positions: [UUID: CGPoint] = [:]
        for value in values.prefix(6) where value.count == 3 && value.allSatisfy(\.isFinite) {
            guard value[0] >= 0, value[0] < Double(characters.count) else { continue }
            let i = Int(value[0]); guard noteTargets.contains(characters[i].id) else { continue }
            positions[characters[i].id] = CGPoint(x: value[1] * viewport.width, y: value[2] * viewport.height)
        }
        notePositions?(positions)
    }
    private func emitLegacyAnchors() {
        guard let view, !noteTargets.isEmpty else { return }
        var positions: [UUID: CGPoint] = [:]
        for i in noteIndices where rigs.indices.contains(i) {
            var top = rigs[i].head.worldPosition; top.y += 0.42
            let p = view.projectPoint(top)
            positions[characters[i].id] = CGPoint(x: p.x, y: viewport.height - p.y)
        }
        notePositions?(positions)
    }
    var onSelect: ((Avatar)->Void)?
    private var simulation=CrowdSimulation(population:0,localCount:0,seed:UInt64.random(in:1...UInt64.max))
    private var crowdConfigured=false
    private var signature=""
    private var gathering: [UUID: UUID] = [:]
    private var appIDs: [UUID] = []
    func setGathering(_ assignments: [UUID: UUID], apps: [UUID]) {
        gathering = assignments; appIDs = apps
        if islandCount != apps.count { islandCount = apps.count }
        updateGathering()
    }
    private func updateGathering() {
        var assignments: [Int: Int] = [:]
        for (avatar, app) in gathering {
            if let walker = characters.firstIndex(where: { $0.id == avatar }), let island = appIDs.firstIndex(of: app) {
                assignments[walker] = island
            }
        }
        simulation.setGatheringIslands(assignments)
    }
    private var timer: Timer?
    private var lastTime=0.0
    private var viewport=CGSize(width:1200,height:720)
    var islandCount=8 { didSet { updateIslands() } }
    private weak var view: SCNView?
    init(size: CGSize) {
        viewport=size; camera.camera=SCNCamera(); camera.camera?.usesOrthographicProjection=true; camera.camera?.wantsHDR=false
        camera.camera?.zNear=0.1; camera.camera?.zFar=100; camera.position=SCNVector3(0,16,22); camera.look(at:SCNVector3Zero)
        world.rootNode.addChildNode(camera); CharacterRig.addLighting(to:world)
    }
    func configure(avatars: [Avatar],population: Int,localCount: Int? = nil) {
        let ownCount=min(avatars.count,max(0,localCount ?? avatars.count))
        let value=String(describing:avatars)+"\(population)-\(ownCount)-\(FFLResources.shared.installed)-\(FFLResources.shared.revision)-\(PlazaBodyResources.shared.revision)"
        guard signature != value else { return }; signature=value
        rigs.forEach { $0.root.removeFromParentNode() }; rigs.removeAll(); characters.removeAll()
        var catalog=avatars
        for i in 0..<16 {
            var a=Avatar(name:"Local visitor",outfit:i%12); a.skin=i%6; a.hair=[33,12,44,0,37,18,55,28,1,93,69,3,30,9,64,58][i]; a.hairColor=[1,2,0,3,1,6,0,2,4,1,3,0,5,6,1,2][i]; a.eyes=[2,0,8,24,18,35,15,40,6,53,32,27,3,59,41,49][i]
            a.brows=[0,1,2,9,4,0,10,1,6,3,8,11,23,9,14,19][i]; a.mouth=[5,0,19,7,14,5,23,8,12,5,3,0,18,34,11,27][i]; a.face=i%12; a.glasses=i%5==0; a.height=Double(i%7)/7; a.build=Double(i%5)/5; a.features.gender=i%2; a.features.eyeColor=i%6; a.features.browColor=a.hairColor; catalog.append(a)
        }
        if !FFLResources.shared.installed { for a in catalog { for mood in [FaceMood.neutral,.happy,.surprised,.speaking] { _=AvatarArtwork.face(a,mood:mood) }; _=AvatarArtwork.face(a,blink:true) } }
        // Geometry and material objects are shared by cloned nodes throughout each character family.
        for i in 0..<population { var a=catalog[i<avatars.count ? i:avatars.count+i%16]; if i>=avatars.count {a.id=UUID(uuidString:String(format:"57415241-0000-4000-8000-%012llx",UInt64(i-avatars.count)))!}; characters.append(a); if !FFLResources.shared.installed { let rig=CharacterRig(a);rig.root.name="character-\(i)";rigs.append(rig);world.rootNode.addChildNode(rig.root) } }
        simulation.worldWidth=PlazaLayout.worldWidth
        simulation.minimumSpacing=0.016
        simulation.groupsBelowIslands=true
        simulation.nominalSpeed = 0.022 * 24 / PlazaLayout.worldWidth
        let original=FFLResources.shared.installed && PlazaBodyResources.shared.installed
        if original {simulation.timing=PlazaBodyResources.shared.motionTiming;simulation.strideLength=1.456;simulation.nominalSpeed=1.456*30/40/PlazaLayout.worldWidth;simulation.scaleSpeedWithStature=true}
        if original,let catalog=PlazaBodyResources.shared.originalCatalog {
            simulation.enableOriginalControllers(catalog)
            simulation.nominalSpeed=1.456*60*0.8461539/40/PlazaLayout.worldWidth
        } else {simulation.disableOriginalControllers()}
        simulation.reconcileRoster(characters.map(\.id),localCount:ownCount)
        simulation.setStatures(characters.map{original ? 0.5+($0.height*127).rounded()*0.77/128:0.72+$0.height*0.40})
        updateGathering();updateGeometry();updateIslands()
        if !crowdConfigured {simulation.step(0.001);crowdConfigured=true}
        fflCharacters=characters
        if fflOwner != nil {rendererReady=false}
        // Deliver the preserved poses before a renderer reconfiguration can
        // draw newly constructed rigs at the previous roster's indices.
        apply();fflConfigure?(characters);fflNoteTargets?(noteIndices)
    }
    private func updateIslands() { simulation.islands=PlazaLayout.slots(for:islandCount).prefix(islandCount).map { CrowdPoint($0.x,$0.y) } }
    func react(to island:Int) {
        let slots=PlazaLayout.slots(for:islandCount);guard slots.indices.contains(island) else {return}
        let p=slots[island];simulation.cheer(near:CrowdPoint(p.x,min(0.93,p.y+simulation.islandBottomClearance+0.04)));apply()
    }
    func selectFFL(_ index:Int) {if characters.indices.contains(index){simulation.acknowledge(index);apply();onSelect?(characters[index])}}
    func select(_ hit: SCNNode?) {
        var node=hit
        while let n=node {
            if let name=n.name,name.hasPrefix("character-"),let i=Int(name.dropFirst(10)),characters.indices.contains(i) { simulation.acknowledge(i);apply();onSelect?(characters[i]); return }
            node=n.parent
        }
    }
    func attachFFL(owner:UUID,frame:@escaping ([[Double]])->Void,configure:@escaping ([Avatar])->Void) {
        fflOwner=owner;fflFrame=frame;fflConfigure=configure;view=nil;rendererReady=false
    }
    func detachFFL(owner:UUID) {
        // SwiftUI can dismantle the outgoing renderer after binding its replacement.
        guard fflOwner==owner else{return}
        fflOwner=nil;fflFrame=nil;fflConfigure=nil;fflNoteTargets=nil;setMoving(false)
    }
    func attach(_ view: SCNView) { fflOwner=nil;fflFrame=nil;fflConfigure=nil;self.view=view;view.scene=world;view.pointOfView=camera;rendererReady=true }
    func detach(_ view:SCNView) { guard fflOwner==nil,self.view===view else{return};setMoving(false);self.view=nil }
    private func updateGeometry() {
        let tile=Double(PlazaLayout.tileSize(in:viewport))
        simulation.worldAspect=Double(16/sqrt(22.0*22+16*16))*Double(viewport.width/viewport.height)
        simulation.islandHalfWidth=(tile/2+10)/Double(viewport.width)
        simulation.islandTopClearance=(tile/2+8)/Double(viewport.height)
        // Feet must leave room for the projected head above them.
        simulation.islandBottomClearance=(tile/2+32+Double(viewport.width)*0.035)/Double(viewport.height)
    }
    func resize(_ size: CGSize) {
        guard size.width>0,size.height>0 else { return }
        camera.camera?.orthographicScale=PlazaLayout.worldWidth/2*Double(size.height/size.width)
        guard size != viewport else { return }
        viewport=size;updateGeometry();updateIslands();apply()
    }
    func setMoving(_ moving: Bool) {
        view?.isPlaying=moving; view?.rendersContinuously=moving
        if moving && timer == nil {
            lastTime=0
            timer=Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !moving { timer?.invalidate(); timer=nil; lastTime=0;entranceClock.pause();arrivalClock.pause();onArrivalStopped?() }
    }
    private func tick() {
        if !rendererReady && (simulation.entranceElapsed != nil || simulation.arrivalElapsed != nil) {lastTime=0;apply();return}
        let now=ProcessInfo.processInfo.systemUptime,dt=lastTime==0 ? 1.0/30:now-lastTime; lastTime=now
        if let elapsed=simulation.entranceElapsed {entranceClock.resume(at:elapsed)}
        if let elapsed=simulation.arrivalElapsed {arrivalClock.resume(at:elapsed)}
        simulation.step(dt); apply()
        if let elapsed=simulation.arrivalElapsed {
            arrivalClock.advance(to:elapsed)
            for cue in PlazaArrival.Cue.allCases where elapsed>=cue.time && arrivalCues.insert(cue).inserted {onArrivalCue?(cue)}
        }
        if simulation.arrivalElapsed == nil && arrivalClock.avatar != nil {arrivalClock.finish()}
        if entrancePrepared && simulation.entranceElapsed == nil && !entranceClock.finished {entranceClock.finish()}
    }
    private func apply() {
        let depth=CGFloat(PlazaLayout.worldWidth*viewport.height/viewport.width)/CGFloat(16/sqrt(22.0*22+16*16))
        if let fflFrame {
            fflFrame(simulation.walkers.enumerated().map { i,w in
                let height=i == simulation.arrivalIndex ? PlazaArrival.height(at:simulation.arrivalElapsed ?? 0):0
                let base=[(w.position.x-0.5)*PlazaLayout.worldWidth,(w.position.y-0.5)*Double(depth),height,w.angle,Double(w.state),w.phase,w.motion,w.partner != nil && w.greeting<=0 ? 1:0,w.blink ? 1:0,Double(w.mood),w.animationTime,w.lookYaw,w.turn,Double(w.activity.rawValue),w.activityTime,w.activityDuration,simulation.animationClock]
                return base+(simulation.originalSample(i)?.bridge ?? [])
            }); return
        }
        SCNTransaction.begin(); SCNTransaction.animationDuration=0; SCNTransaction.disableActions=true
        for i in rigs.indices where i<simulation.walkers.count {
            let w=simulation.walkers[i],rig=rigs[i]
            let drop=i == simulation.arrivalIndex ? PlazaArrival.height(at:simulation.arrivalElapsed ?? 0):0
            let bounce=CGFloat(CharacterMotion.solve(state:w.state,phase:w.phase,amount:w.motion,time:w.animationTime).hop)*rig.stature+CGFloat(drop)
            let position=SCNVector3(CGFloat(w.position.x-0.5)*PlazaLayout.worldWidth,bounce,CGFloat(w.position.y-0.5)*depth),old=rig.root.position
            if abs(position.x-old.x)+abs(position.y-old.y)+abs(position.z-old.z)>0.00002 {rig.root.position=position}
            if abs(rig.root.eulerAngles.y-CGFloat(w.angle))>0.00002 {rig.root.eulerAngles.y=CGFloat(w.angle)}; rig.pose(state:w.state,phase:CGFloat(w.phase),amount:CGFloat(w.motion),delta:1.0/30,social:w.partner != nil && w.greeting<=0,time:w.animationTime,lookYaw:w.lookYaw,turn:w.turn); rig.setFace(blink:w.blink,mood:FaceMood(rawValue:w.mood) ?? .neutral)
        }
        SCNTransaction.commit(); if view?.rendersContinuously != true {view?.needsDisplay=true}
        emitLegacyAnchors()
    }
    deinit { timer?.invalidate() }
}

struct LegacySceneView: NSViewRepresentable {
    let scene: PlazaScene
    var moving: Bool
    var onSelect: (Avatar)->Void
    func makeNSView(context: Context) -> PlazaRenderView {
        let view=PlazaRenderView(); view.owner=scene; view.backgroundColor = .clear; view.preferredFramesPerSecond=30; view.antialiasingMode = .multisampling2X
        view.setAccessibilityElement(false); scene.attach(view); return view
    }
    func updateNSView(_ view: PlazaRenderView,context: Context) { scene.onSelect=onSelect; scene.setMoving(moving); scene.resize(view.bounds.size) }
    static func dismantleNSView(_ view: PlazaRenderView,coordinator: ()) { view.owner?.detach(view) }
}
final class PlazaRenderView: SCNView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    weak var owner: PlazaScene?
    override func mouseDown(with event: NSEvent) {
        let point=convert(event.locationInWindow,from:nil)
        owner?.select(hitTest(point,options:[.searchMode:SCNHitTestSearchMode.closest.rawValue]).first?.node)
    }
    override func layout() { super.layout(); owner?.resize(bounds.size) }
}
