import Foundation

public struct CrowdPoint: Equatable, Sendable {
    public var x:Double;public var y:Double
    public init(_ x:Double,_ y:Double) {self.x=x;self.y=y}
}
public struct CrowdWalker: Equatable, Sendable {
    public var position:CrowdPoint
    public var target:CrowdPoint
    public var angle=0.0
    public var phase=0.0
    /// Time for idle/gesture animation is independent of distance-driven footfalls.
    public var animationTime=0.0
    public var lookYaw=0.0
    public var turn=0.0
    public var gaitScale=1.0
    public var wait=0.0
    public var state=0 // idle, walk, turn, wave, celebrate, react
    public var blink=false
    public var speed=0.0
    public var motion=0.0
    public var partner:Int?
    public var conversation=0.0
    public var greeting=0.0
    public var cue=0.0
    public var cooldown=0.0
    public var mood=0 // neutral, happy, surprised, speaking
    public var activity=CrowdActivity.rest
    public var activityTime=0.0
    public var activityDuration=0.0
    public var activityDelay=0.0
    public var exchangeDuration=0.0
    public var stuck=0.0
    public var path:[CrowdPoint]=[]
    public var originalSocialAction=25
    public var originalSocialRate:Float=1
    public var originalSocialTicks=0
    public var originalSocialDuration=0
    public var originalSocialLeader=false
    public var originalHeading=OriginalLoungeHeading()
    public var originalMotion=OriginalLoungeMotion()
    public var originalFacingTarget:Double?
}
/// Deterministic crowd with walking acceleration, obstacle routes and reciprocal social pairs.
/// Rendering consumes snapshots directly; animation never publishes per-frame SwiftUI state.
public struct CrowdSimulation: Sendable {
    public private(set) var walkers:[CrowdWalker]=[]
    public var islands:[CrowdPoint]=[] {didSet {buildNavigation()}}
    public var worldAspect=1.0
    public var worldWidth=24.0
    public var minimumSpacing=0.058
    public var groupsBelowIslands=false
    public private(set) var gatheringIslands: [Int: Int] = [:]
    /// Host-supplied app affinity. Retarget walkers without moving their current position.
    public mutating func setGatheringIslands(_ assignments: [Int: Int]) {
        let valid = assignments.filter { walkers.indices.contains($0.key) && $0.value >= 0 }
        let changed = Set(gatheringIslands.keys).union(valid.keys).filter { gatheringIslands[$0] != valid[$0] }
        gatheringIslands = valid
        if usesOriginalControllers {synchronizeOriginalGroups()}
        if placed {
            for i in changed where walkers.indices.contains(i) {
                if walkers[i].partner == nil {
                    walkers[i].target = destination(i)
                    walkers[i].path = route(from: walkers[i].position, to: walkers[i].target)
                }
                walkers[i].wait = 0
            }
        }
    }
    public var islandHalfWidth=0.079
    public var islandTopClearance=0.084
    public var islandBottomClearance=0.234
    private var sourceWidth:Double { worldWidth*40 }
    public var timing=CrowdTiming()
    public var strideLength=0.48
    public var nominalSpeed=0.022
    public var scaleSpeedWithStature=false
    public mutating func setStatures(_ values:[Double]) {
        for i in walkers.indices where values.indices.contains(i) {
            walkers[i].gaitScale=min(1.30,max(0.50,values[i]))
        }
    }
    private var navigation:[CrowdPoint]=[]
    private var navigationEdges:[[Double]]=[]
    private var placed=false
    private var random:SeededRandom
    private var localCount:Int
    private var roster:[UUID]=[]
    private var rosterOrdinals:[UInt64]=[]
    private struct RetainedActor:Sendable {
        var walker:CrowdWalker
        var partner:UUID?
        var player:OriginalLoungePlayback?
        var idle:OriginalLoungeIdle?
    }
    private var retainedActors:[UUID:RetainedActor]=[:]
    private var elapsed=0.0
    private var originalCatalog:OriginalLoungeCatalog?
    private var originalPlayers:[OriginalLoungePlayback]=[]
    private var originalIdles:[OriginalLoungeIdle]=[]
    private var originalRandom=OriginalLoungeRandom(seed:0x57415241)
    private var originalRemainder=0.0
    private var originalGroups:[OriginalLoungeGroupDatabase]=[]
    private var originalGroupGeometry:[Double]=[]
    private var originalGroupCursor=0
    private var controllerTicksPerSecond=60.0
    public var usesOriginalControllers:Bool {originalCatalog != nil}
    public private(set) var automaticDanceStarts=0
    /// Native host adapter. The recovered routines count updates/source frames;
    /// 60 Hz is this host's cadence, not a claim of a measured Wii U frame rate.
    public mutating func enableOriginalControllers(_ catalog:OriginalLoungeCatalog,ticksPerSecond:Double=60) {
        guard ticksPerSecond.isFinite,(30...120).contains(ticksPerSecond) else{return}
        if originalCatalog?.clips == catalog.clips && controllerTicksPerSecond == ticksPerSecond {return}
        originalCatalog=catalog;controllerTicksPerSecond=ticksPerSecond;originalRemainder=0
        for id in Array(retainedActors.keys) {retainedActors[id]?.player=nil;retainedActors[id]?.idle=nil}
        originalPlayers=walkers.map {_ in OriginalLoungePlayback(catalog:catalog)}
        originalIdles=walkers.map {_ in OriginalLoungeIdle()}
        for i in walkers.indices {
            walkers[i].originalMotion.target=sourcePoint(walkers[i].position)
            walkers[i].originalMotion.runStyle=OriginalLounge.runStyle(random:&originalRandom)
        }
        timing=CrowdTiming(clips:Dictionary(uniqueKeysWithValues:catalog.clips.map {($0.name,Double($0.frames)/ticksPerSecond)}))
        for i in walkers.indices {walkers[i].wait=destinationWait(i)}
    }
    public mutating func disableOriginalControllers() {
        originalCatalog=nil;originalPlayers=[];originalIdles=[];originalRemainder=0
        for id in Array(retainedActors.keys) {retainedActors[id]?.player=nil;retainedActors[id]?.idle=nil}
    }
    /// Reconcile identity changes without restarting clocks, random streams,
    /// animation phases or surviving pairs. Temporarily hidden actors retain
    /// their state for safe mode, population and power-mode changes.
    public mutating func reconcileRoster(_ identities:[UUID],localCount:Int) {
        guard identities.count <= Preferences.populationRange.upperBound,
              Set(identities).count == identities.count else{return}
        self.localCount=min(identities.count,max(0,localCount))
        if roster == identities {return}
        if roster.isEmpty && walkers.count == identities.count {
            roster=identities;rosterOrdinals=identities.map(Self.stableOrdinal);return
        }
        for (i,id) in roster.enumerated() where walkers.indices.contains(i) {
            retainedActors[id]=RetainedActor(walker:walkers[i],
                partner:walkers[i].partner.flatMap {roster.indices.contains($0) ? roster[$0]:nil},
                player:originalPlayers.indices.contains(i) ? originalPlayers[i]:nil,
                idle:originalIdles.indices.contains(i) ? originalIdles[i]:nil)
        }
        let oldRoster=roster
        let oldGoals=Dictionary(uniqueKeysWithValues:oldRoster.enumerated().compactMap {i,id in
            entranceGoals.indices.contains(i) ? (id,(entranceGoals[i],entranceRanks[i])):nil
        })
        let arriving=arrivalIndex.flatMap {oldRoster.indices.contains($0) ? oldRoster[$0]:nil}
        let indices=Dictionary(uniqueKeysWithValues:identities.enumerated().map {($0.element,$0.offset)})
        let remapping=Dictionary(uniqueKeysWithValues:oldRoster.enumerated().compactMap {i,id in indices[id].map {(i,$0)}})
        for g in originalGroups.indices {originalGroups[g].remapActors(remapping)}
        let oldGathering=gatheringIslands
        gatheringIslands=Dictionary(uniqueKeysWithValues:oldGathering.compactMap {i,app in
            oldRoster.indices.contains(i) ? indices[oldRoster[i]].map {($0,app)}:nil
        })
        roster=identities;rosterOrdinals=identities.map(Self.stableOrdinal);walkers=[];originalPlayers=[];originalIdles=[]
        var added:[Int]=[]
        for (i,id) in identities.enumerated() {
            if let saved=retainedActors[id] {
                var actor=saved.walker
                actor.partner=saved.partner.flatMap {indices[$0]}
                if actor.partner == nil && saved.partner != nil {
                    actor.conversation=0;actor.greeting=0;actor.originalSocialAction=25
                    actor.originalSocialTicks=0;actor.originalSocialLeader=false
                    actor.target=actor.position;actor.path=[];actor.wait=max(1,actor.wait)
                    actor.originalMotion.walking=false;actor.originalMotion.state = .rest;actor.originalMotion.speed=0
                }
                walkers.append(actor)
                if let catalog=originalCatalog {
                    originalPlayers.append(saved.player ?? OriginalLoungePlayback(catalog:catalog))
                    originalIdles.append(saved.idle ?? OriginalLoungeIdle())
                }
            } else {
                let p=CrowdPoint(0.1+random.unit()*0.8,0.25+random.unit()*0.68)
                var actor=CrowdWalker(position:p,target:p)
                actor.wait=6+random.unit()*18;actor.phase=Double(i)*1.73;actor.cooldown=random.unit()*3
                walkers.append(actor);added.append(i)
                if let catalog=originalCatalog {
                    walkers[i].originalMotion.runStyle=OriginalLounge.runStyle(random:&originalRandom)
                    originalPlayers.append(OriginalLoungePlayback(catalog:catalog));originalIdles.append(OriginalLoungeIdle())
                }
            }
        }
        for i in walkers.indices {
            if let j=walkers[i].partner,walkers[j].partner != i {
                walkers[i].partner=nil;walkers[i].conversation=0;walkers[i].originalSocialAction=25
                walkers[i].originalSocialTicks=0;walkers[i].originalSocialLeader=false
            }
        }
        if placed {
            for i in added {
                let p=destination(i);walkers[i].position=p;walkers[i].target=p
                walkers[i].originalMotion.target=sourcePoint(p)
            }
        }
        if entranceElapsed != nil {
            entranceGoals=identities.enumerated().map {oldGoals[$0.element]?.0 ?? walkers[$0.offset].position}
            entranceRanks=identities.enumerated().map {oldGoals[$0.element]?.1 ?? $0.offset}
        }
        arrivalIndex=arriving.flatMap {indices[$0]}
        if arrivalIndex == nil {arrivalElapsed=nil}
        if retainedActors.count>1000 {
            for id in retainedActors.keys.sorted(by:{$0.uuidString<$1.uuidString}) where indices[id] == nil {
                retainedActors.removeValue(forKey:id)
                if retainedActors.count<=1000 {break}
            }
        }
    }
    public func originalSample(_ index:Int)->OriginalLoungePlayback.Sample? {
        guard originalPlayers.indices.contains(index) else{return nil}
        let idle=originalPlayers[index].sample
        if let time=entranceElapsed,let catalog=originalCatalog,let run=catalog.clip(animation:4) {
            let rank=entranceRanks[index]
            let progress=PlazaEntrance.progress(index:rank,goal:entranceGoals[index],elapsed:time)
            let arrival=PlazaEntrance.arrivalTime(index:rank,goal:entranceGoals[index])
            let blend=Float(min(1,max(0,(time-arrival)/0.3)))
            if progress<1 || blend<1 {
                let frame=Float(time*60+Double(rank)*3).truncatingRemainder(dividingBy:catalog.clips[run].frames)
                return .init(clip:progress<1 ? run:idle.clip,frame:progress<1 ? frame:idle.frame,
                             previousClip:run,previousFrame:frame,blend:progress<1 ? 1:blend,revision:10000+index)
            }
        }
        return idle
    }
    private mutating func destinationWait(_ i:Int)->Double {
        if usesWalkways(i) { return 2+random.unit()*7 }
        // Original destination refresh, 0x0218a8f8. Source destination search
        // uses native world bounds; visibility routes adapt Mac controls.
        return usesOriginalControllers ? Double(300+originalRandom.below(1500))/controllerTicksPerSecond:10+random.unit()*18
    }
    private func originalMayWalk(_ i:Int)->Bool {
        !usesOriginalControllers || (originalPlayers[i].stage == .main && (3...7).contains(originalPlayers[i].animation))
    }
    private func originalMaySocialize(_ i:Int)->Bool {
        !usesOriginalControllers || (10...25).contains(originalPlayers[i].animation)
    }
    public var animationClock:Double {elapsed}
    public private(set) var arrivalIndex:Int?
    public private(set) var arrivalElapsed:Double?
    public mutating func beginArrival(index:Int) {
        guard walkers.indices.contains(index) else{return}
        finishEntrance();finishArrival();endPair(index)
        arrivalIndex=index;arrivalElapsed=0
        holdArrival(index)
    }
    public mutating func finishArrival() {
        guard let i=arrivalIndex else{return}
        arrivalIndex=nil;arrivalElapsed=nil
        walkers[i].greeting=0;walkers[i].state=0;walkers[i].activity = .rest
        walkers[i].wait=0;walkers[i].cooldown=3
        walkers[i].target=destination(i)
        walkers[i].path=route(from:walkers[i].position,to:walkers[i].target)
    }
    private mutating func holdArrival(_ i:Int) {
        let waving=(arrivalElapsed ?? 0)>=PlazaArrival.landing
        walkers[i].position=PlazaArrival.center;walkers[i].target=PlazaArrival.center;walkers[i].path=[]
        walkers[i].angle=0;walkers[i].lookYaw=0;walkers[i].turn=0
        walkers[i].speed=0;walkers[i].motion=0;walkers[i].wait=PlazaArrival.duration
        walkers[i].cooldown=PlazaArrival.duration;walkers[i].greeting=waving ? 1:0
        walkers[i].state=waving ? 3:0;walkers[i].activity=waving ? .wave:.rest
        walkers[i].animationTime=max(0,(arrivalElapsed ?? 0)-PlazaArrival.landing)
        walkers[i].activityDuration=PlazaArrival.duration-PlazaArrival.landing
        walkers[i].activityTime=walkers[i].animationTime;walkers[i].mood=waving ? 1:0
        walkers[i].originalMotion = OriginalLoungeMotion()
    }
    private var entranceGoals:[CrowdPoint]=[]
    private var entranceRanks:[Int]=[]
    public private(set) var entranceElapsed:Double?
    public mutating func beginEntrance() {
        guard entranceElapsed == nil, !walkers.isEmpty else {return}
        entranceGoals=walkers.map(\.position);entranceRanks=Array(walkers.indices);entranceElapsed=0
        for i in walkers.indices {
            walkers[i].position=PlazaEntrance.position(index:i,goal:entranceGoals[i],elapsed:0)
            walkers[i].target=entranceGoals[i]
        }
    }
    public mutating func finishEntrance() {
        guard entranceElapsed != nil else{return}
        for i in walkers.indices {
            walkers[i].position=entranceGoals[i];walkers[i].target=entranceGoals[i]
            walkers[i].state=0;walkers[i].motion=0;walkers[i].speed=0
        }
        entranceGoals=[];entranceRanks=[];entranceElapsed=nil
    }
    private mutating func stepEntrance(_ dt:Double) {
        let time=min(PlazaEntrance.duration,(entranceElapsed ?? 0)+dt)
        entranceElapsed=time;elapsed+=dt
        for i in walkers.indices {
            let next=PlazaEntrance.position(index:entranceRanks[i],goal:entranceGoals[i],elapsed:time)
            let old=walkers[i].position,travel=distance(old,next)*worldWidth
            let arriving=PlazaEntrance.progress(index:entranceRanks[i],goal:entranceGoals[i],elapsed:time)<1
            walkers[i].position=next;walkers[i].animationTime+=dt
            walkers[i].phase+=travel/(max(0.05,strideLength)*walkers[i].gaitScale)*2 * .pi
            walkers[i].state=arriving ? 1:0;walkers[i].motion=arriving ? 1:0
            if travel>0.00001 {walkers[i].angle=facing(old,next)}
        }
        if time>=PlazaEntrance.duration {finishEntrance()}
    }
    public init(population:Int,localCount:Int,seed:UInt64=0x57415241) {
        random=SeededRandom(seed:seed);self.localCount=localCount
        originalRandom=OriginalLoungeRandom(seed:UInt32(truncatingIfNeeded:seed))
        for i in 0..<min(Preferences.populationRange.upperBound,max(0,population)) {
            let p=CrowdPoint(0.1+random.unit()*0.8,0.25+random.unit()*0.68)
            var w=CrowdWalker(position:p,target:p);w.wait=6+random.unit()*18;w.phase=Double(i)*1.73;w.cooldown=random.unit()*3;walkers.append(w)
        }
    }
    /// Internal host entry point for restoring a known placement. Controller
    /// activation remains explicit so restored actors use the installed catalog.
    init(placement:[CrowdWalker],localCount:Int,seed:UInt64) {
        self.init(population:placement.count,localCount:localCount,seed:seed)
        walkers=Array(placement.prefix(walkers.count))
        placed=true
    }
    private func blocked(_ p:CrowdPoint) -> Bool {islands.contains {abs(p.x-$0.x)<islandHalfWidth && p.y>$0.y-islandTopClearance && p.y<$0.y+islandBottomClearance}}
    private func obstacleDepth(_ p:CrowdPoint)->Double {
        islands.reduce(0) {depth,c in
            let x=islandHalfWidth-abs(p.x-c.x)
            let y=min(p.y-(c.y-islandTopClearance),c.y+islandBottomClearance-p.y)
            return depth+max(0,min(x,y))
        }
    }
    /// A resized/replaced app control may cover a standing actor. Permit only
    /// progress out of the overlap, rather than relocating the actor instantly.
    private func traversable(_ a:CrowdPoint,_ b:CrowdPoint)->Bool {
        if blocked(a) {return obstacleDepth(b)<obstacleDepth(a)-1e-10}
        return !blocked(b) && clear(a,b)
    }
    private func escapeDestination(_ p:CrowdPoint)->CrowdPoint? {
        var candidates:[CrowdPoint]=[]
        for c in islands where abs(p.x-c.x)<islandHalfWidth && p.y>c.y-islandTopClearance && p.y<c.y+islandBottomClearance {
            candidates += [CrowdPoint(c.x-islandHalfWidth-0.01,p.y),CrowdPoint(c.x+islandHalfWidth+0.01,p.y),
                CrowdPoint(p.x,c.y-islandTopClearance-0.01),CrowdPoint(p.x,c.y+islandBottomClearance+0.01)]
        }
        return candidates.filter {(0.05...0.95).contains($0.x) && (0.20...0.95).contains($0.y) && !blocked($0)}
            .min {distance(p,$0)<distance(p,$1)}
    }
    private var aspect:Double {min(4,max(0.25,worldAspect))}
    // Source body scale is 40; keep distances consistent with the camera width.
    private func sourcePoint(_ p:CrowdPoint)->OriginalLounge.GroundPoint {
        .init(Float((p.x-0.5)*sourceWidth),Float((p.y-0.575)/aspect*sourceWidth))
    }
    private func hostPoint(_ p:OriginalLounge.GroundPoint)->CrowdPoint {
        CrowdPoint(Double(p.x)/sourceWidth+0.5,Double(p.z)/sourceWidth*aspect+0.575)
    }
    private func partnerInput(_ i:Int)->OriginalLounge.PartnerInput {
        let w=walkers[i],player=originalPlayers[i]
        var input=OriginalLounge.PartnerInput(position:sourcePoint(w.position),
            forward:.init(Float(sin(w.angle)),Float(cos(w.angle))),animation:player.animation)
        input.hasWatchTarget=w.greeting>0;input.hasPartner=w.partner != nil
        input.socialTicks=w.cooldown>0 ? -1:w.originalSocialTicks
        var flags=OriginalLounge.RestrictionInput()
        flags.animationID=Int32(player.animation);flags.animationFlags=player.flags
        flags.movementState=Int32(walkers[i].originalMotion.state.rawValue)
        flags.has3a0=input.hasWatchTarget;flags.has3b4=input.hasPartner
        input.restrictions=OriginalLounge.restrictions(flags)
        if arrivalIndex == i {input.restrictions |= 3;input.hasWatchTarget=true}
        return input
    }
    private func distance(_ a:CrowdPoint,_ b:CrowdPoint) -> Double {hypot(a.x-b.x,(a.y-b.y)/aspect)}
    private func clear(_ a:CrowdPoint,_ b:CrowdPoint) -> Bool {
        for c in islands {
            let lo=[c.x-islandHalfWidth,c.y-islandTopClearance],hi=[c.x+islandHalfWidth,c.y+islandBottomClearance],origin=[a.x,a.y],delta=[b.x-a.x,b.y-a.y]
            var near=0.0,far=1.0,intersects=true
            for axis in 0..<2 {
                if abs(delta[axis])<0.000001 {if origin[axis]<=lo[axis] || origin[axis]>=hi[axis] {intersects=false;break}}
                else {let t1=(lo[axis]-origin[axis])/delta[axis],t2=(hi[axis]-origin[axis])/delta[axis];near=max(near,min(t1,t2));far=min(far,max(t1,t2));if near>far {intersects=false;break}}
            }
            if intersects {return false}
        }
        return true
    }
    private mutating func buildNavigation() {
        navigation=[]
        for c in islands {for x in [c.x-islandHalfWidth-0.013,c.x+islandHalfWidth+0.013] {for y in [c.y-islandTopClearance-0.013,c.y+islandBottomClearance+0.013] {
            let p=CrowdPoint(x,y)
            if (0.05...0.95).contains(x) && (0.20...0.95).contains(y) && !blocked(p) {navigation.append(p)}
        }}}
        navigationEdges=navigation.map {a in navigation.map {b in clear(a,b) ? distance(a,b):Double.infinity}}
        // Initial placement is spaced around app groups, not a synchronized march
        // from random positions. Subsequent routing never relocates a walker.
        if !placed && !islands.isEmpty && !walkers.isEmpty {
            for i in walkers.indices {
                let p=destination(i);walkers[i].position=p;walkers[i].target=p
                walkers[i].angle=i<localCount ? (random.unit()-0.5)*0.6:random.unit()*2 * .pi
                if groupsBelowIslands && i<localCount {walkers[i].wait=0.4+Double(i)*0.3}
                else if usesWalkways(i) {walkers[i].wait=2+random.unit()*7}
            }
            placed=true
        }
    }
    /// Small visibility graph, evaluated only when choosing a new destination.
    private func route(from start:CrowdPoint,to end:CrowdPoint) -> [CrowdPoint] {
        if clear(start,end) {return [end]}
        let points=[start,end]+navigation,n=points.count
        var costs=Array(repeating:Double.infinity,count:n),previous=Array(repeating:-1,count:n),visited=Array(repeating:false,count:n);costs[0]=0
        for _ in 0..<n {
            guard let u=(0..<n).filter({!visited[$0]}).min(by:{costs[$0]<costs[$1]}),costs[u].isFinite else {break}
            if u==1 {break};visited[u]=true
            for v in 1..<n where !visited[v] {
                let edge=u>=2 && v>=2 ? navigationEdges[u-2][v-2]:(clear(points[u],points[v]) ? distance(points[u],points[v]):Double.infinity)
                let cost=costs[u]+edge;if cost<costs[v] {costs[v]=cost;previous[v]=u}
            }
        }
        guard costs[1].isFinite else {return []}
        var path:[CrowdPoint]=[],i=1
        while i>0 {path.insert(points[i],at:0);i=previous[i];if i<0 {return []}}
        return path
    }
    // Mix the visitor index so roaming roles do not repeat at the same icons
    // when their count shares a divisor with the crowd's distribution.
    private func actorOrdinal(_ i:Int)->UInt64 {
        rosterOrdinals.indices.contains(i) ? rosterOrdinals[i]:UInt64(max(0,i-localCount))
    }
    private static func stableOrdinal(_ identity:UUID)->UInt64 {
        let id=identity.uuidString
        if id.hasPrefix("57415241-0000-4000-8000-"),let slot=UInt64(id.suffix(12),radix:16) {return slot}
        return id.utf8.reduce(UInt64(14695981039346656037)) {($0 ^ UInt64($1)) &* 1099511628211}
    }
    private func usesWalkways(_ i:Int)->Bool {
        guard groupsBelowIslands,i>=localCount,gatheringIslands[i]==nil else{return false}
        var value=(actorOrdinal(i) &+ 1) &* 0x9E3779B97F4A7C15
        value=(value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        return (value ^ (value >> 27))%100<35
    }
    private func groupCenter(_ slot:Int)->CrowdPoint {
        let c=islands[slot]
        return CrowdPoint(c.x+sin(Double(slot)*2.4)*0.012,min(0.90,c.y+islandBottomClearance+0.045))
    }
    private mutating func destination(_ i:Int) -> CrowdPoint {
        let current=walkers[i].position
        if usesOriginalControllers,let p=originalGroupTarget(i),!blocked(p) {return p}
        let gathering = gatheringIslands[i].flatMap { islands.indices.contains($0) ? $0 : nil }
        let roaming=usesWalkways(i)
        if gathering == nil && usesOriginalControllers && !groupsBelowIslands {
            let circles=islands.map { c in OriginalLounge.NavigationObstacle(
                center:sourcePoint(CrowdPoint(c.x,c.y+(islandBottomClearance-islandTopClearance)/2)),radius:Float(max(islandHalfWidth,(islandTopClearance+islandBottomClearance)/2/aspect)*sourceWidth)) }
            // Source item circles guide destination selection. Mac controls use
            // rectangles, so host validation and visibility routes remain here.
            for _ in 0..<4 {
                if let chosen=OriginalLounge.destination(from:sourcePoint(current),role:i<localCount ? 1:0,
                    halfWidth:Float(0.45*sourceWidth),halfDepth:Float(0.375*sourceWidth/aspect),obstacles:circles,random:&originalRandom) {
                    let p=hostPoint(chosen)
                    if (0.05...0.95).contains(p.x),(0.20...0.95).contains(p.y),!blocked(p) {return p}
                }
            }
            if !blocked(current) {return current}
            // Only initial/layout recovery falls through to native placement.
        }
        var best=current,bestScore = -Double.infinity
        let wander=gathering == nil && !groupsBelowIslands && placed && random.unit()<0.16
        let home=gathering ?? Int(actorOrdinal(i)%UInt64(max(1,islands.count)))
        let slot=wander && !islands.isEmpty ? Int(random.unit()*Double(islands.count)):home
        for _ in 0..<(roaming ? 120:60) {
            var p:CrowdPoint
            if roaming {
                // Open ground between gatherings, rather than another tiny
                // app circle. Exclude group cores so the lanes remain visible.
                p=CrowdPoint(0.07+random.unit()*0.86,0.23+random.unit()*0.69)
                if islands.indices.contains(where:{distance(p,groupCenter($0))<0.085}) {continue}
                if placed && distance(current,p)<0.08 {continue}
            } else if gathering == nil && i<localCount && ((!placed && groupsBelowIslands) || random.unit()<0.75) {
                p=groupsBelowIslands ? CrowdPoint(0.42+random.unit()*0.16,0.43+random.unit()*0.14):CrowdPoint(0.34+random.unit()*0.32,0.71+random.unit()*0.17)
            }
            else if !islands.isEmpty {
                let c=islands[min(islands.count-1,slot)],theta=random.unit()*2 * .pi
                if groupsBelowIslands {
                    let center=groupCenter(min(islands.count-1,slot))
                    let radius=sqrt(random.unit()),spread=0.85+Double(slot%3)*0.12
                    p=CrowdPoint(center.x+cos(theta)*radius*0.085*spread,center.y+sin(theta)*radius*0.052)
                } else {
                    p=CrowdPoint(c.x+cos(theta)*(0.035+random.unit()*0.13),c.y+(c.y<0.67 ? 0.29:-0.17)+sin(theta)*(0.025+random.unit()*0.09))
                }
            } else {p=CrowdPoint(0.10+random.unit()*0.8,0.25+random.unit()*0.65)}
            guard (0.05...0.95).contains(p.x),(0.20...0.95).contains(p.y),!blocked(p) else{continue}
            var spacing=0.12
            for j in walkers.indices where j != i {
                spacing=min(spacing,distance(p,walkers[j].position),distance(p,walkers[j].target))
            }
            let score=min(spacing,minimumSpacing)*8-(placed ? distance(current,p)*0.07:0)
            if score>bestScore {best=p;bestScore=score}
            if spacing>minimumSpacing*0.91 {return p}
        }
        // Short windows can leave no room directly beneath a foreground tile.
        // Recover into an open walkway instead of returning a blocked origin.
        if !bestScore.isFinite {
            for _ in 0..<256 {
                let p=CrowdPoint(0.05+random.unit()*0.90,0.20+random.unit()*0.75)
                if !blocked(p) { return p }
            }
        }
        return best
    }
    private func activity(_ kind:CrowdActivity,_ w:inout CrowdWalker,duration:Double?=nil) {
        if w.activity != kind {w.activity=kind;w.activityTime=0;w.activityDuration=duration ?? timing.duration(kind)}
    }
    private mutating func endPair(_ i:Int) {
        if let j=walkers[i].partner {walkers[j].partner=nil;walkers[j].conversation=0;walkers[j].greeting=0;walkers[j].cooldown=10;walkers[j].activity = .rest;walkers[j].wait=4}
        walkers[i].partner=nil;walkers[i].conversation=0;walkers[i].greeting=0
    }
    public mutating func cheer(near point:CrowdPoint) {
        let nearby=walkers.indices.filter {distance(walkers[$0].position,point)<0.23 && walkers[$0].activity != .sit}.sorted {distance(walkers[$0].position,point)<distance(walkers[$1].position,point)}.prefix(6)
        var dancing=Set<Int>()
        if usesOriginalControllers {
            // An app reaction is a native event. Within that event use the
            // source side-by-side predicate and selector without snapping or
            // forcing ineligible visitors into a dance.
            for i in nearby where !dancing.contains(i) {
                for j in nearby where j != i && !dancing.contains(j) {
                    if OriginalLounge.acceptsDance(partnerInput(i),partnerInput(j)) {
                        let start=OriginalLounge.startDance(random:&originalRandom)
                        setOriginalPair(i,j,transition:.init(action:start.firstAction,partnerAction:start.secondAction,durationTicks:start.durationTicks,rate:1))
                        walkers[i].originalSocialLeader=true;walkers[j].originalSocialLeader=false
                        dancing.insert(i);dancing.insert(j);break
                    }
                }
            }
        }
        for (rank,i) in nearby.enumerated() where !dancing.contains(i) {
            endPair(i)
            walkers[i].cue=timing.duration(.cheer)+Double(rank)*0.12
            walkers[i].activity = .cheer;walkers[i].activityTime = -Double(rank)*0.12;walkers[i].activityDuration=timing.duration(.cheer)
            walkers[i].animationTime=0;walkers[i].path=[];walkers[i].target=walkers[i].position;walkers[i].wait=5;walkers[i].cooldown=10
        }
    }
    /// A selected visitor finishes a complete original greeting sequence.
    public mutating func acknowledge(_ index:Int) {
        guard walkers.indices.contains(index),walkers[index].partner==nil,walkers[index].activity != .sit else{return}
        walkers[index].path=[];walkers[index].target=walkers[index].position
        walkers[index].wait=timing.wave+3;walkers[index].cooldown=10;walkers[index].greeting=timing.wave;walkers[index].animationTime=0
        walkers[index].activity = .wave;walkers[index].activityTime=0;walkers[index].activityDuration=timing.wave
    }
    private func facing(_ from:CrowdPoint,_ to:CrowdPoint) -> Double {atan2((to.x-from.x)*min(4,max(0.25,worldAspect)),to.y-from.y)}
    private func turned(_ current:Double,toward target:Double,dt:Double,rate:Double=3.5) -> Double {
        let d=atan2(sin(target-current),cos(target-current));return current+max(-rate*dt,min(rate*dt,d))
    }
    private func turn(_ walker:inout CrowdWalker,toward target:Double,dt:Double,gain:Float,limit:Float,fallbackRate:Double) {
        if usesOriginalControllers {
            walker.originalHeading.angle=Float(walker.angle)
            walker.originalHeading.step(toward:Float(target),gain:gain,limit:limit)
            walker.angle=Double(walker.originalHeading.angle)
        } else {walker.angle=turned(walker.angle,toward:target,dt:dt,rate:fallbackRate)}
    }
    public mutating func step(_ delta:Double) {
        guard delta.isFinite,delta>0 else{return}
        if entranceElapsed != nil {stepEntrance(min(0.1,delta));return}
        if usesOriginalControllers {
            let dt=1/controllerTicksPerSecond
            originalRemainder+=min(0.1,delta)
            while originalRemainder+1e-10>=dt {
                stepFrame(dt);advanceOriginalSocial();advanceOriginalControllers();originalRemainder=max(0,originalRemainder-dt)
            }
        } else {stepFrame(min(0.05,delta))}
        if let time=arrivalElapsed,time>=PlazaArrival.duration {finishArrival()}
    }
    private mutating func stepOriginalWalk(_ i:Int,_ w:inout CrowdWalker,goal:CrowdPoint,dt:Double) {
        let player=originalPlayers[i],catalog=originalCatalog!
        let length=catalog.clips[catalog.clip(animation:player.animation)!].frames
        let position=sourcePoint(w.position),destination=sourcePoint(goal)
        let forward=OriginalLounge.GroundPoint(Float(sin(w.angle)),Float(cos(w.angle)))
        // A new source movement request copies its destination immediately;
        // subsequent waypoint changes use the recovered 0.05 smoothing.
        if !w.originalMotion.walking && w.state != 2 {w.originalMotion.target=destination}
        if w.originalMotion.state == .rest {w.originalMotion.direction=forward}
        let delta=w.originalMotion.locomote(position:position,goal:destination,forward:forward,
            frame:player.stage == .main ? player.frame:0,length:length,
            height:Float(min(1,max(0,(w.gaitScale-0.5)/0.77))),assigned:originalGroupTarget(i) != nil,
            canStart:originalMayWalk(i),animation:player.animation,
            animationComplete:player.complete(catalog) && player.blendWeight>=1,random:&originalRandom)
        if originalMayWalk(i) && w.originalMotion.state == .rest {
            if !w.path.isEmpty {w.path.removeFirst()}
            if w.path.isEmpty {w.target=w.position}
        }
        if delta.x != 0 || delta.z != 0 {
            turn(&w,toward:Double(atan2(w.originalMotion.direction.x,w.originalMotion.direction.z)),dt:dt,gain:0.2,limit:0.4,fallbackRate:3.5)
            let next=hostPoint(.init(position.x+delta.x,position.z+delta.z))
            if traversable(w.position,next),(0.05...0.95).contains(next.x),(0.20...0.95).contains(next.y) {
                w.phase+=hypot(Double(delta.x),Double(delta.z))/40/(max(0.05,strideLength)*w.gaitScale)*2 * .pi
                w.position=next;w.stuck=0
                let newForward=OriginalLounge.GroundPoint(Float(sin(w.angle)),Float(cos(w.angle)))
                w.originalMotion.gaitDistance=max(0,(delta.x*newForward.x).addingProduct(delta.z,newForward.z))
            } else {
                w.originalMotion.displacement = .init(0,0);w.originalMotion.gaitDistance=0
                w.stuck+=dt
                if w.stuck>2.5 {w.path=[];w.target=w.position;w.wait=1;w.stuck=0;w.originalMotion.walking=false;w.originalMotion.state = .rest;w.originalMotion.speed=0}
            }
        }
        w.speed=Double(w.originalMotion.speed)*controllerTicksPerSecond/sourceWidth
        w.state=w.originalMotion.walking ? 1:distance(w.position,w.path.first ?? w.target)>6/sourceWidth ? 2:0
        w.motion+=(min(1,Double(w.originalMotion.speed)/0.25)-w.motion)*min(1,dt*10)
        w.originalFacingTarget=nil;w.lookYaw=0;activity(.rest,&w)
    }
    /// Native collider queries feed the recovered contact/impulse controller.
    /// Snapshot order replaces Wii U owner locks. Radius and dominant-contact
    /// selection remain host geometry adapters, not recovered collider code.
    private mutating func advanceOriginalCollisions(previous snapshot:[CrowdWalker]) {
        let positions=walkers.map {sourcePoint($0.position)}
        let inputs=walkers.indices.map {partnerInput($0)}
        var cells:[Int:[Int]]=[:]
        func key(_ x:Int,_ z:Int)->Int {z*4096+x}
        for i in positions.indices {let p=positions[i];cells[key(Int(floor(p.x/32)),Int(floor(p.z/32))),default:[]].append(i)}
        for i in walkers.indices where i != arrivalIndex {
            let p=positions[i],cx=Int(floor(p.x/32)),cz=Int(floor(p.z/32))
            var neighbors:[OriginalLounge.NavigationObstacle]=[],dominant:Int?,penetration:Float=0
            for z in (cz-1)...(cz+1) {for x in (cx-1)...(cx+1) {for j in cells[key(x,z)] ?? [] where j != i {
                let other=positions[j],dx=other.x-p.x,dz=other.z-p.z
                let squared=(dx*dx).addingProduct(dz,dz)
                if squared<256 {
                    neighbors.append(.init(center:other,radius:8))
                    let overlap=16-squared.squareRoot()
                    if overlap>penetration {dominant=j;penetration=overlap}
                }
            }}}
            var collision=walkers[i].originalMotion.collision
            let separation=OriginalLounge.separation(position:p,radius:8,neighbors:neighbors)
            let neighborDelta=dominant.map {OriginalLounge.GroundPoint(positions[$0].x-p.x,positions[$0].z-p.z)}
            let relative=dominant.map {OriginalLounge.GroundPoint(snapshot[$0].originalMotion.displacement.x-snapshot[i].originalMotion.displacement.x,snapshot[$0].originalMotion.displacement.z-snapshot[i].originalMotion.displacement.z)} ?? .init(0,0)
            let (contact,opposed)=collision.contact(separation,direction:walkers[i].originalMotion.direction,
                neighborDelta:neighborDelta,relativeMovement:relative,neighborMovable:dominant.map {inputs[$0].restrictions & 2 == 0} ?? true)
            let move=collision.integrate(contact,opposed:opposed,forward:inputs[i].forward,
                stature:Float(walkers[i].gaitScale),blocked:inputs[i].restrictions & 2 != 0)
            let next=hostPoint(.init(p.x+move.x,p.z+move.z))
            if move != .init(0,0),traversable(walkers[i].position,next),(0.05...0.95).contains(next.x),(0.20...0.95).contains(next.y) {walkers[i].position=next}
            walkers[i].originalMotion.collision=collision
            if let j=dominant,walkers[i].originalMotion.state == .rest,walkers[i].path.isEmpty,
               walkers[i].partner==nil,!(81...84).contains(inputs[i].animation),!(34...45).contains(inputs[i].animation),
               (4...6).contains(inputs[j].animation) {
                let motion=snapshot[j].originalMotion
                let velocity=OriginalLounge.GroundPoint(motion.direction.x*motion.speed,motion.direction.z*motion.speed)
                if let reaction=OriginalLounge.collisionReaction(delta:collision.reactionDelta ?? neighborDelta!,forward:inputs[i].forward,velocity:velocity,restrictions:inputs[i].restrictions),
                   let catalog=originalCatalog {
                    _=originalIdles[i].react(reaction,playback:&originalPlayers[i],catalog:catalog)
                }
                // Original +314 destination refresh, including rejected reactions.
                walkers[i].wait=Double(120+originalRandom.below(180))/controllerTicksPerSecond
            }
            let old=sourcePoint(snapshot[i].position),current=sourcePoint(walkers[i].position)
            walkers[i].originalMotion.displacement = .init(current.x-old.x,current.z-old.z)
        }
    }
    private func groupSlot(_ i:Int)->Int? {
        guard !islands.isEmpty else{return nil}
        if let g=gatheringIslands[i],islands.indices.contains(g) {return g}
        return groupsBelowIslands && i>=localCount && !usesWalkways(i) ? Int(actorOrdinal(i)%UInt64(islands.count)):nil
    }
    private func originalGroupTarget(_ i:Int)->CrowdPoint? {
        guard let g=groupSlot(i),originalGroups.indices.contains(g),let n=originalGroups[g].node(for:i) else{return nil}
        let p=hostPoint(originalGroups[g].nodes[n].position)
        return validGroupPoint(p) ? p:nil
    }
    private func validGroupPoint(_ p:CrowdPoint)->Bool {
        (0.05...0.95).contains(p.x) && (0.20...0.95).contains(p.y) && !blocked(p)
    }
    /// The 397-node databases retain occupancy across layout and roster updates.
    /// Admission, app membership and one-group-per-tick scheduling are Mac host
    /// boundaries. Source swaps update goals; they never relocate an actor.
    private mutating func synchronizeOriginalGroups() {
        guard !islands.isEmpty else{originalGroups=[];originalGroupGeometry=[];return}
        while originalGroups.count<islands.count {originalGroups.append(OriginalLoungeGroupDatabase())}
        if originalGroups.count>islands.count {originalGroups.removeLast(originalGroups.count-islands.count)}
        let geometry=[sourceWidth,aspect,islandBottomClearance]+islands.flatMap {[$0.x,$0.y]}
        if geometry != originalGroupGeometry {
            originalGroupGeometry=geometry
            for g in originalGroups.indices {originalGroups[g].setGeometry(origin:sourcePoint(groupCenter(g)))}
        }
        for g in originalGroups.indices {
            for n in originalGroups[g].occupied {
                if let a=originalGroups[g].nodes[n].actor,groupSlot(a) != g || !validGroupPoint(hostPoint(originalGroups[g].nodes[n].position)) {originalGroups[g].remove(actor:a)}
            }
        }
        for i in walkers.indices {
            guard let g=groupSlot(i),originalGroups[g].node(for:i)==nil else{continue}
            let p=sourcePoint(walkers[i].position)
            let candidate=originalGroups[g].nodes.indices.filter {n in
                guard originalGroups[g].nodes[n].actor==nil else{return false}
                let point=hostPoint(originalGroups[g].nodes[n].position)
                return validGroupPoint(point)
            }.min {a,b in
                let pa=originalGroups[g].nodes[a].position,pb=originalGroups[g].nodes[b].position
                return hypot(pa.x-p.x,pa.z-p.z)<hypot(pb.x-p.x,pb.z-p.z)
            }
            if let n=candidate {_=originalGroups[g].insert(actor:i,at:n)}
        }
    }
    private mutating func advanceOriginalGroups() {
        synchronizeOriginalGroups()
        guard !originalGroups.isEmpty else{return}
        let g=originalGroupCursor%originalGroups.count;originalGroupCursor=(g+1)%originalGroups.count
        let positions=walkers.map {sourcePoint($0.position)},restrictions=walkers.indices.map {partnerInput($0).restrictions}
        let old=originalGroups[g]
        let node=Int(originalRandom.below(UInt32(old.nodes.count)))
        if old.nodes[node].actor != nil {_=originalGroups[g].optimize(from:node,positions:positions,restrictions:restrictions,random:&originalRandom)}
        for n in originalGroups[g].occupied {
            guard let i=originalGroups[g].nodes[n].actor,walkers[i].partner==nil,
                  let previous=old.node(for:i),previous != n else{continue}
            let goal=hostPoint(originalGroups[g].nodes[n].position)
            if validGroupPoint(goal) {walkers[i].target=goal;walkers[i].path=route(from:walkers[i].position,to:goal)}
        }
    }
    /// Recovered automatic dance/facing opportunity path from 0217f074.
    /// Greeting/watch/message handlers remain outside this dispatch adapter.
    private mutating func advanceOriginalGroupEvents() {
        guard !walkers.isEmpty else{return}
        let i=Int(originalRandom.below(UInt32(walkers.count))),input=partnerInput(i)
        guard walkers[i].originalMotion.state == .rest,input.restrictions & 1 == 0 else{return}
        guard let g=groupSlot(i),originalGroups.indices.contains(g),let node=originalGroups[g].node(for:i) else{return}
        let slots=originalGroups[g].slots(at:node)
        var candidate:Int?
        if originalRandom.unit()<Float(0.01)*Float(walkers.count) {
            candidate=OriginalLounge.groupNeighbor(slots:slots,mask:OriginalLounge.groupDirectionMask(input.forward),random:&originalRandom)
            if let j=candidate,OriginalLounge.acceptsGroupFacing(input,at:partnerInput(j).position),
                OriginalLounge.acceptsGroupFacing(partnerInput(j),at:input.position) {
                // Source greeting-attempt draw remains; the unported greeting
                // controller is treated as rejecting, then source turn requests.
                _=originalRandom.unit()
                for (k,other) in [(i,j),(j,i)] {
                    let angle=facing(walkers[k].position,walkers[other].position)
                    let difference=atan2(sin(angle-walkers[k].angle),cos(angle-walkers[k].angle))
                    let fraction=Float(0.5).addingProduct(originalRandom.unit(),0.5)
                    walkers[k].originalFacingTarget=walkers[k].angle+difference*Double(fraction)
                }
                _=OriginalLounge.groupNeighbor(slots:slots,random:&originalRandom)
                return
            }
            candidate=nil
        }
        if OriginalLounge.automaticDanceGate(population:walkers.count,random:&originalRandom) {
            let right=OriginalLounge.GroundPoint(input.forward.z,-input.forward.x)
            candidate=OriginalLounge.groupNeighbor(slots:slots,mask:OriginalLounge.groupDirectionMask(right),random:&originalRandom)
            if let j=candidate,OriginalLounge.acceptsDance(input,partnerInput(j)) {
                let start=OriginalLounge.startDance(random:&originalRandom)
                setOriginalPair(i,j,transition:.init(action:start.firstAction,partnerAction:start.secondAction,durationTicks:start.durationTicks,rate:1))
                walkers[i].originalSocialLeader=true;walkers[j].originalSocialLeader=false
                automaticDanceStarts+=1
                _=OriginalLounge.groupNeighbor(slots:slots,random:&originalRandom)
                return
            }
        }
        if candidate == nil,originalRandom.unit()<Float(0.01)*Float(walkers.count) {
            let degrees=OriginalLounge.groupTurn(forward:input.forward,random:&originalRandom)
            walkers[i].originalFacingTarget=walkers[i].angle+Double(degrees)*Double.pi/180
        }
        _=OriginalLounge.groupNeighbor(slots:slots,random:&originalRandom)
    }
    private mutating func stepFrame(_ delta:Double) {
        guard delta.isFinite,delta>0 else {return};let dt=min(0.05,delta);elapsed+=dt
        if let time=arrivalElapsed {arrivalElapsed=time+dt}
        if usesOriginalControllers {advanceOriginalGroups()}
        for i in walkers.indices where i != arrivalIndex && blocked(walkers[i].position) {
            if let escape=escapeDestination(walkers[i].position) {
                if walkers[i].partner != nil {endPair(i)}
                if walkers[i].path.isEmpty || blocked(walkers[i].target) || !traversable(walkers[i].position,walkers[i].path[0]) {
                    walkers[i].target=escape;walkers[i].path=[escape];walkers[i].wait=0
                }
            }
        }
        var cells:[Int:[Int]]=[:]
        func key(_ x:Int,_ y:Int) -> Int {y*64+x}
        for i in walkers.indices {let p=walkers[i].position;cells[key(Int(p.x/0.055),Int(p.y/0.055)),default:[]].append(i)}
        let before=walkers
        for i in walkers.indices {
            if i == arrivalIndex {holdArrival(i);continue}
            var w=walkers[i];w.cooldown=max(0,w.cooldown-dt);w.animationTime+=dt;w.activityTime+=dt
            w.originalMotion.gaitDistance=0
            let oldAngle=w.angle
            if w.cue>0 {
                w.cue=max(0,w.cue-dt);w.state=w.activityTime<0 ? 0:4;w.mood=1;w.speed=0;w.motion*=max(0,1-dt*8)
            } else if let j=w.partner, before.indices.contains(j),w.conversation>0 {
                w.conversation=max(0,w.conversation-dt);w.greeting=max(0,w.greeting-dt);w.speed=0;w.motion*=max(0,1-dt*8)
                if usesOriginalControllers {
                    let desired=facing(w.position,before[j].position)
                    let error=abs(atan2(sin(desired-w.angle),cos(desired-w.angle)))
                    let player=originalPlayers[i],other=originalPlayers[j]
                    let length=originalCatalog!.clips[originalCatalog!.clip(animation:player.animation)!].frames
                    let frame:Float=player.stage == .main ? player.frame:0
                    let otherFrame:Float=other.stage == .main ? other.frame:0
                    originalPlayers[i].setRate(OriginalLounge.pairedRate(frame:frame,partnerFrame:otherFrame,length:length))
                    if let dance=OriginalLounge.dancePosition(action:w.originalSocialAction,position:sourcePoint(w.position),
                        partner:sourcePoint(before[j].position),mainFrame:frame,length:length) {
                        let next=hostPoint(dance.position)
                        if !blocked(next),(0.05...0.95).contains(next.x),(0.20...0.95).contains(next.y) {w.position=next;w.target=next}
                        if dance.tangent.x != 0 || dance.tangent.z != 0 {
                            turn(&w,toward:Double(atan2(dance.tangent.x,dance.tangent.z)),dt:dt,gain:dance.headingGain,limit:1,fallbackRate:2.2)
                        }
                    } else if error > .pi/4 {
                        let side=sin(desired-w.angle)>0 ? 1.0:-1.0
                        turn(&w,toward:w.angle+side * .pi/2,dt:dt,gain:0.01,limit:1.5,fallbackRate:2.2)
                    }
                    w.state=0;w.lookYaw=0;w.mood=w.originalSocialAction==1 ? 3:0
                    w.activity=w.originalSocialAction==0 ? .bow:w.originalSocialAction==1 ? .talk:.listen
                    walkers[i]=w;continue
                }
                w.angle=turned(w.angle,toward:facing(w.position,before[j].position),dt:dt,rate:2.2)
                let t=w.exchangeDuration-w.conversation,hello=0.6+timing.wave+0.18
                if t<hello {
                    if t<0.6+w.activityDelay {activity(.rest,&w);w.state=0;w.mood=0}
                    else {activity(.wave,&w);w.state=3;w.mood=1}
                } else if w.conversation<=timing.bow {
                    activity(.bow,&w);w.state=5;w.mood=1
                } else {
                    let speaking=(Int((t-hello)/timing.talk)%2==0)==(i<j)
                    activity(speaking ? .talk:.listen,&w)
                    w.state=speaking ? 3:5;w.mood=speaking && Int(w.activityTime*5)%4 != 0 ? 3:0
                }
                w.lookYaw=0
                if w.conversation<=0 {w.partner=nil;w.cooldown=12+random.unit()*12;w.wait=4+random.unit()*8;w.state=0;w.mood=0;activity(.rest,&w)}
            } else {
                w.partner=nil;w.mood=0
                if !usesOriginalControllers,let first=w.path.first,distance(w.position,first)<0.004 {w.path.removeFirst()}
                if usesOriginalControllers,!w.originalMotion.walking,let first=w.path.first,distance(w.position,first)<6/sourceWidth {
                    w.path.removeFirst()
                    if w.path.isEmpty {w.target=w.position}
                }
                let goal=w.path.first ?? w.target,dx=goal.x-w.position.x,dy=goal.y-w.position.y,d=hypot(dx,dy),topSpeed=nominalSpeed*(0.92+Double(i%5)*0.04)*(scaleSpeedWithStature ? w.gaitScale:1)
                if usesOriginalControllers && (w.originalMotion.state != .rest || d>6/sourceWidth) {
                    stepOriginalWalk(i,&w,goal:goal,dt:dt)
                } else if !usesOriginalControllers && d>0.004 {
                    if !originalMayWalk(i) {
                        w.state=2;w.speed=0;w.motion*=max(0,1-dt*10);activity(.rest,&w)
                        walkers[i]=w;continue
                    }
                    let desired=facing(w.position,goal),angleError=atan2(sin(desired-w.angle),cos(desired-w.angle))
                    turn(&w,toward:desired,dt:dt,gain:0.2,limit:0.4,fallbackRate:3.5)
                    var desiredSpeed=topSpeed*max(0,cos(angleError))*min(1,d/0.018)
                    let cx=Int(w.position.x/0.055),cy=Int(w.position.y/0.055)
                    // Look ahead and yield before contact, with a stable passing side.
                    var avoidX=0.0,avoidY=0.0
                    for y in (cy-2)...(cy+2) {for x in (cx-2)...(cx+2) {for j in cells[key(x,y)] ?? [] where j != i {
                        let ox=before[j].position.x-w.position.x,oy=(before[j].position.y-w.position.y)/aspect,sep=hypot(ox,oy)
                        let forward=ox*sin(desired)+oy*cos(desired),side=ox*cos(desired)-oy*sin(desired)
                        let reach=usesOriginalControllers ? 0.035:min(0.075,minimumSpacing*2.6)
                        let width=usesOriginalControllers ? 8.0/sourceWidth:min(0.036,minimumSpacing*1.1)
                        if sep<reach && forward>0 && abs(side)<width {
                            let contact=usesOriginalControllers ? 12.0/sourceWidth:min(0.033,minimumSpacing*0.9)
                            desiredSpeed*=min(1,max(0,(sep-contact)/(reach-contact)))
                            let pass=abs(side)<width/3 ? 1.0:(side>0 ? -1.0:1.0)
                            avoidX+=cos(desired)*pass*(reach-sep)*0.22;avoidY-=sin(desired)*pass*(reach-sep)*0.22
                        }
                    }}}
                    w.speed+=max(-dt*0.10,min(dt*0.055,desiredSpeed-w.speed));w.state=abs(angleError)>0.65 ? 2:1
                    activity(.rest,&w)
                    // Constant world speed at every window aspect, not faster along the depth axis.
                    let physicalDistance=hypot(dx,dy/min(4,max(0.25,worldAspect)))
                    let steering=min(1,w.speed/max(0.001,topSpeed))
                    var next=CrowdPoint(w.position.x+(dx/physicalDistance*w.speed+avoidX*steering)*dt,w.position.y+(dy/physicalDistance*w.speed+avoidY*aspect*steering)*dt)
                    for y in (cy-1)...(cy+1) {for x in (cx-1)...(cx+1) {for j in cells[key(x,y)] ?? [] where j != i {
                        let sx=next.x-before[j].position.x,sy=(next.y-before[j].position.y)/aspect,separation=hypot(sx,sy)
                        let clearance=min(0.033,minimumSpacing*0.95)
                        if separation>0.0001 && separation<clearance {let push=(clearance-separation)/clearance*dt*0.018*steering;next.x+=sx/separation*push;next.y+=sy/separation*push*aspect}
                    }}}
                    next.x=min(0.95,max(0.05,next.x));next.y=min(0.95,max(0.20,next.y))
                    if traversable(w.position,next) {
                        let travel=hypot((next.x-w.position.x)*worldWidth,(next.y-w.position.y)*worldWidth/min(4,max(0.25,worldAspect)))
                        w.phase+=travel/(max(0.05,strideLength)*w.gaitScale)*2 * .pi;w.position=next
                    } else {w.speed*=0.6}
                    w.stuck=distance(w.position,before[i].position)<topSpeed*dt*0.10 ? w.stuck+dt:0
                    if w.stuck>2.5 {w.path=[];w.target=w.position;w.wait=1+random.unit()*2;w.stuck=0}
                    w.motion+=(min(1,w.speed/topSpeed)-w.motion)*min(1,dt*10)
                    w.lookYaw=atan2(sin(desired-w.angle),cos(desired-w.angle))*0.35
                } else {
                    w.speed=0;w.motion*=max(0,1-dt*10);w.wait-=dt
                    w.originalMotion.walking=false;w.originalMotion.speed=0;w.originalMotion.gaitDistance=0
                    w.originalMotion.state = .rest
                    if let target=w.originalFacingTarget {
                        turn(&w,toward:target,dt:dt,gain:0.1,limit:1,fallbackRate:2.2)
                        if abs(target-w.angle)<0.001 {w.originalFacingTarget=nil}
                    }
                    w.greeting=max(0,w.greeting-dt)
                    if w.activityTime>=w.activityDuration && w.activity != .rest {activity(.rest,&w)}
                    if w.greeting>0 {activity(.wave,&w);turn(&w,toward:0,dt:dt,gain:0.3,limit:1,fallbackRate:2.2)}
                    if !usesOriginalControllers && w.activity == .rest && w.wait>6 && w.cooldown<=0 && random.unit()<dt*0.055 {
                        let choices:[CrowdActivity]=[.lookAround,.lookAround,.scratch,.yawn,.sit,.surprise,.cheer]
                        let kind=choices[min(choices.count-1,Int(random.unit()*Double(choices.count)))];activity(kind,&w);w.wait=max(w.wait,w.activityDuration+3);w.cooldown=w.activityDuration+8
                    }
                    w.state=w.activity == .wave ? 3:w.activity == .cheer ? 4:w.activity == .surprise ? 5:0
                    w.mood=w.activity == .wave || w.activity == .cheer ? 1:0
                    w.lookYaw=sin(w.animationTime*0.43+Double(i)*1.9)*0.20
                    if w.wait<=0 && w.activity == .rest {
                        w.target=destination(i);w.path=route(from:w.position,to:w.target)
                        if w.path.isEmpty {w.target=w.position};w.wait=destinationWait(i)
                    }
                }
            }
            w.turn+=(atan2(sin(w.angle-oldAngle),cos(w.angle-oldAngle))/dt-w.turn)*min(1,dt*8)
            w.blink=(elapsed+Double(i)*0.77).truncatingRemainder(dividingBy:4.1+Double(i%4)*0.33)<0.13
            walkers[i]=w
        }
        if usesOriginalControllers {advanceOriginalCollisions(previous:before);advanceOriginalGroupEvents()}
        if let catalog=originalCatalog,let bow=catalog.clip(animation:111) {
            // Original query takes the first mutually eligible neighbor, not
            // the nearest visitor or a probabilistic per-second match. Native
            // index order replaces the menu's spatial database iteration order.
            let inputs=walkers.indices.map {partnerInput($0)}
            for i in walkers.indices where walkers[i].partner==nil && (10...25).contains(inputs[i].animation) {
                let input=inputs[i],p=walkers[i].position,cx=Int(p.x/0.055),cy=Int(p.y/0.055)
                var candidates:[Int]=[]
                // Wider depth window covers aspect ratios up to four.
                for y in (cy-2)...(cy+2) {for x in (cx-1)...(cx+1) {candidates += cells[key(x,y)] ?? []}}
                for j in candidates.sorted() where j>i && walkers[j].partner==nil {
                    let other=inputs[j]
                    if OriginalLounge.acceptsPartner(input,at:other.position),
                       OriginalLounge.acceptsPartner(other,at:input.position),clear(walkers[i].position,walkers[j].position) {
                        let start=OriginalLounge.startSocial(bowFrames:catalog.clips[bow].frames,random:&originalRandom)
                        setOriginalPair(i,j,transition:.init(action:start.firstAction,partnerAction:start.secondAction,durationTicks:start.durationTicks,rate:1))
                        walkers[i].originalSocialLeader=start.firstLeader;walkers[j].originalSocialLeader = !start.firstLeader
                        break
                    }
                }
            }
            return
        }
        // Resource-free fallback.
        for i in walkers.indices where walkers[i].partner==nil && walkers[i].state==0 && walkers[i].activity == .rest && walkers[i].cooldown<=0 && walkers[i].wait>2.5 && originalMaySocialize(i) {
            guard random.unit()<dt*0.7 else {continue}
            let p=walkers[i].position,cx=Int(p.x/0.055),cy=Int(p.y/0.055)
            var nearest:Int?,best=0.085
            for y in (cy-2)...(cy+2) {for x in (cx-2)...(cx+2) {for j in cells[key(x,y)] ?? [] where j>i && walkers[j].partner==nil && walkers[j].state==0 && walkers[j].activity == .rest && walkers[j].cooldown<=0 && walkers[j].wait>2.5 && originalMaySocialize(j) {
                let d=distance(p,walkers[j].position);if d>0.043 && d<best && clear(p,walkers[j].position) {nearest=j;best=d}
            }}}
            if let j=nearest {
                let duration=0.6+timing.wave+0.18+timing.talk*Double(2+Int(random.unit()*3))+timing.bow
                for k in [i,j] {walkers[k].partner=k==i ? j:i;walkers[k].conversation=duration;walkers[k].exchangeDuration=duration;walkers[k].greeting=0.6+timing.wave+0.18;walkers[k].activityDelay=k==i ? 0:0.18;walkers[k].animationTime=0;walkers[k].activity = .rest;walkers[k].activityTime=0;walkers[k].path=[];walkers[k].target=walkers[k].position}
            }
        }
    }
    private mutating func setOriginalPair(_ leader:Int,_ follower:Int,transition:OriginalLounge.SocialTransition) {
        for k in [leader,follower] {
            walkers[k].partner=k==leader ? follower:leader
            walkers[k].originalSocialAction=k==leader ? transition.action:transition.partnerAction
            walkers[k].originalSocialLeader=k==follower
            walkers[k].originalSocialRate=transition.rate
            walkers[k].originalSocialTicks=0;walkers[k].originalSocialDuration=transition.durationTicks
            walkers[k].conversation=Double(transition.durationTicks+2)/controllerTicksPerSecond
            walkers[k].greeting=0;walkers[k].path=[];walkers[k].target=walkers[k].position
            walkers[k].originalMotion.state = .rest;walkers[k].originalMotion.walking=false;walkers[k].originalMotion.speed=0
        }
    }
    private mutating func advanceOriginalSocial() {
        guard let catalog=originalCatalog else{return}
        for i in walkers.indices {
            guard let j=walkers[i].partner,j>i else{continue}
            let leader=walkers[i].originalSocialLeader ? i:j,other=leader==i ? j:i
            walkers[i].originalSocialTicks+=1;walkers[j].originalSocialTicks+=1
            guard walkers[leader].originalSocialTicks>walkers[leader].originalSocialDuration else{continue}
            if let action=OriginalLounge.nextSocialAction(after:walkers[leader].originalSocialAction,random:&originalRandom),
               let transition=OriginalLounge.socialTransition(action:action,catalog:catalog,random:&originalRandom) {
                setOriginalPair(leader,other,transition:transition)
            } else {
                endPair(i)
                for k in [i,j] {
                    walkers[k].originalSocialAction=25
                    walkers[k].cooldown=Double(OriginalLounge.socialCooldown(random:&originalRandom))/controllerTicksPerSecond
                }
            }
        }
    }
    /// Recovered animation/ordinary-idle controllers driven by native host inputs.
    /// The Mac host supplies geometry and app reactions.
    private mutating func advanceOriginalControllers() {
        guard let catalog=originalCatalog else{return}
        for i in walkers.indices {
            originalPlayers[i].finishStages(catalog:catalog)
            let w=walkers[i]
            var requested:Int?
            if w.cue>0 && w.activityTime>=0 {requested=126}
            else if w.partner != nil {requested=OriginalLounge.socialAnimation(action:w.originalSocialAction)}
            else if w.greeting>0 {
                switch w.activity {
                case .wave:requested=110
                case .talk:requested=OriginalLounge.socialAnimation(action:1)
                case .listen:requested=OriginalLounge.socialAnimation(action:2)
                case .bow:requested=OriginalLounge.socialAnimation(action:0)
                default:requested=0
                }
            } else if w.originalMotion.state != .rest {requested=w.originalMotion.requestedAnimation}
            else if w.state==1 || w.state==2 || distance(w.position,w.path.first ?? w.target)>6/sourceWidth {requested=3}
            if let requested {
                // Original walk rate clamp, 0x02196e04. Native distance is mapped
                // into source gait units; routes and body scale are host inputs.
                let rate:Float=(3...7).contains(requested) ? w.originalMotion.animationRate(stature:Float(w.gaitScale)):w.partner != nil ? w.originalSocialRate:1
                originalPlayers[i].request(requested,catalog:catalog,rate:rate)
                if (3...7).contains(requested) {originalPlayers[i].setRate(rate)}
            } else {
                var context=OriginalLounge.IdleContext()
                context.groupDensity=walkers.reduce(0) {count,other in count+(distance(w.position,other.position)<0.10 ? 1:0)}-1
                originalIdles[i].step(playback:&originalPlayers[i],catalog:catalog,random:&originalRandom,context:context)
            }
            originalPlayers[i].advance(catalog:catalog)
            let id=originalPlayers[i].animation
            if (34...45).contains(id) {
                walkers[i].activity = .sit
                walkers[i].wait=max(walkers[i].wait,Double(max(0,originalIdles[i].holdingTicks-originalIdles[i].baselineTicks)+1)/controllerTicksPerSecond)
            } else if requested==nil {
                switch id {
                case 54,55:walkers[i].activity = .lookAround
                case 61:walkers[i].activity = .scratch
                case 62:walkers[i].activity = .yawn
                default:walkers[i].activity = .rest
                }
            }
        }
    }
}
