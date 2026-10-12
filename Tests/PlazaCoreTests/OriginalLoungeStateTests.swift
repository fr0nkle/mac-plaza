import XCTest
@testable import PlazaCore

final class OriginalLoungeStateTests:XCTestCase {
    func testStateAnimationSelectionAndBreathingCooldown() {
        var m=OriginalLoungeMotion(),r=OriginalLoungeRandom(seed:42)
        let expected=[0,3,4,7,1,60,2]
        for state in 0...6 {m.state = .init(rawValue:state)!;XCTAssertEqual(m.requestedAnimation,expected[state])}
        m.state = .run;m.runStyle=1;XCTAssertEqual(m.requestedAnimation,5)
        m.runStyle=2;XCTAssertEqual(m.requestedAnimation,6)
        m.state = .tired;m.speed=0.49
        m.decide(squaredDistance:10000,frame:0,length:40,random:&r)
        XCTAssertEqual(m.state,.blowOut);XCTAssertEqual(m.speed,0.5)
        m.decide(squaredDistance:10000,frame:40,length:40,animation:2,animationComplete:true,random:&r)
        XCTAssertEqual(m.state,.walk);XCTAssertEqual(m.runCooldown,300)
        for _ in 0..<300 {m.decide(squaredDistance:160000,frame:0,length:40,random:&r);XCTAssertEqual(m.state,.walk)}
        m.decide(squaredDistance:160000,frame:0,length:40,random:&r);XCTAssertEqual(m.state,.run)
    }
    func testFixedDatabaseOccupancyAndRaySearch() {
        var db=OriginalLoungeGroupDatabase()
        XCTAssertEqual(db.nodes.count,397);XCTAssertEqual(Set(db.nodes.map(\.axial)).count,397)
        for (i,n) in db.nodes.enumerated() {
            for (slot,neighbor) in n.neighbors.enumerated() {if let j=neighbor {XCTAssertEqual(db.nodes[j].neighbors[(slot+3)%6],i)}}
        }
        let first=db.nodes[0].neighbors[3]!,second=db.nodes[first].neighbors[3]!
        XCTAssertTrue(db.insert(actor:1,at:0));XCTAssertTrue(db.insert(actor:2,at:second))
        XCTAssertEqual(db.firstOccupied(from:0,direction:3),second)
        XCTAssertEqual(db.nodes[first].occupiedNeighbors,2)
        db.swap(0,second);XCTAssertEqual(db.nodes[0].actor,2);XCTAssertEqual(db.nodes[0].order,0)
        db.move(second,to:first);XCTAssertEqual(db.occupied,[0,first]);XCTAssertEqual(db.nodes[first].actor,1)
        db.remapActors([1:7]);XCTAssertEqual(db.occupied,[first]);XCTAssertEqual(db.nodes[first].actor,7)
        for node in db.nodes {XCTAssertEqual(node.occupiedNeighbors,node.neighbors.compactMap {$0}.filter {db.nodes[$0].actor != nil}.count)}
        let before=db.nodes.map(\.actor)
        db.setGeometry(origin:.init(20,30),radius:9)
        XCTAssertEqual(before,db.nodes.map(\.actor));XCTAssertEqual(db.nodes[0].position,.init(20,30))
    }
    func testOptimizationSwapsAssignmentsWithoutChangingActorPositions() {
        var db=OriginalLoungeGroupDatabase(),r=OriginalLoungeRandom(seed:42)
        let b=db.nodes[0].neighbors[3]!,positions=[db.nodes[b].position,db.nodes[0].position]
        _=db.insert(actor:0,at:0);_=db.insert(actor:1,at:b)
        _=db.optimize(from:0,positions:positions,restrictions:[0,0],random:&r)
        XCTAssertEqual(db.nodes[0].actor,1);XCTAssertEqual(db.nodes[b].actor,0)
        XCTAssertEqual(positions,[db.nodes[b].position,db.nodes[0].position])
        XCTAssertFalse(OriginalLoungeGroupDatabase.improvesSwap(nodeA:.init(0,0),nodeB:.init(16,0),actorA:.init(16,0),actorB:.init(0,0),restrictionsA:0x20))
    }
    func testCollisionReactionsFinishBeforeReturningToIdle() throws {
        let catalog=try XCTUnwrap(OriginalLoungeCatalog(clips:Set(OriginalLounge.animations.map(\.name)).sorted().map { .init(name:$0,frames:12,loop:$0.hasSuffix("_l")) }))
        var player=OriginalLoungePlayback(catalog:catalog),idle=OriginalLoungeIdle()
        let reaction=try XCTUnwrap(OriginalLounge.collisionReaction(delta:.init(10,0),forward:.init(0,1),velocity:.init(0,1)))
        XCTAssertEqual(reaction.type,3)
        XCTAssertTrue(idle.react(reaction,playback:&player,catalog:catalog))
        for _ in 0..<60 {
            idle.step(playback:&player,catalog:catalog,random:&idleRandom,context:.init())
            XCTAssertEqual(player.animation,84)
            player.advance(catalog:catalog)
        }
        idle.step(playback:&player,catalog:catalog,random:&idleRandom,context:.init())
        XCTAssertEqual(player.animation,10)
    }
    func testReactionUsesContactWorkingVectorIncludingDegeneratePerpendicular() {
        var collision=OriginalLoungeCollision()
        _=collision.contact(.init(0,-2),direction:.init(0,1),neighborDelta:.init(0,10),relativeMovement:.init(0,-1))
        XCTAssertEqual(collision.reactionDelta,.init(0,0))
        XCTAssertNil(OriginalLounge.collisionReaction(delta:collision.reactionDelta!,forward:.init(0,1),velocity:.init(0,-1)))
        _=collision.contact(.init(-2,-2),direction:.init(0,1),neighborDelta:.init(6,8),relativeMovement:.init(0,-1))
        XCTAssertEqual(collision.reactionDelta,.init(1,0))
    }
    private var idleRandom=OriginalLoungeRandom(seed:42)
    func testStatesDatabaseAndReactionsAgainstOriginalInstructions() throws {
        guard let path=ProcessInfo.processInfo.environment["PLAZA_ORIGINAL_LOGIC_QA"] else {throw XCTSkip("Set PLAZA_ORIGINAL_LOGIC_QA to local instruction fixtures")}
        struct Vectors:Decodable {let locomotion,groupCoordinates,groupSwaps,collisionReactions,groupOptimizations:[[Double]]}
        let v=try JSONDecoder().decode(Vectors.self,from:Data(contentsOf:URL(fileURLWithPath:path)))
        XCTAssertGreaterThan(v.locomotion.count,1000);XCTAssertEqual(v.groupCoordinates.count,397);XCTAssertEqual(v.collisionReactions.count,140)
        var states=Set<Int>()
        for (i,a) in v.locomotion.enumerated() {
            var m=OriginalLoungeMotion(),r=OriginalLoungeRandom(seed:UInt32(a[9]))
            m.state = .init(rawValue:Int(a[0]))!;m.speed=Float(a[3]);m.stateTicks=Int(a[4])-1;m.runStyle=Int(a[5]);m.runCooldown=Int(a[6])
            m.target = .init(0,Float(a[2]));m.ramp=1
            _=m.locomote(position:.init(0,0),goal:m.target,forward:.init(0,1),frame:a[7]==1 ? 40:15,length:40,
                special:a[8]==1,assigned:a[1]==1,animation:Int(a[10]),animationComplete:a[7]==1,random:&r)
            XCTAssertEqual(m.state.rawValue,Int(a[11]),"state fixture \(i)");states.insert(m.state.rawValue)
            XCTAssertEqual(m.stateTicks,Int(a[12]),"ticks fixture \(i)");XCTAssertEqual(m.runCooldown,Int(a[13]))
            XCTAssertEqual(m.speed,Float(a[14]),accuracy:2e-6,"speed fixture \(i)")
            XCTAssertEqual(m.direction.x,Float(a[15]),accuracy:2e-6);XCTAssertEqual(m.direction.z,Float(a[16]),accuracy:2e-6)
            XCTAssertEqual(r.words,a[17..<21].map {UInt32($0)},"RNG fixture \(i)")
        }
        XCTAssertEqual(states,Set(0...6))
        XCTAssertTrue(v.locomotion.contains {$0[0]==2 && $0[11]==3},"Fixtures must enter tired from running")
        XCTAssertTrue(v.locomotion.contains {$0[0]==2 && $0[11]==4},"Fixtures must enter fall from running")
        for a in v.groupCoordinates {
            let p=OriginalLoungeGroupDatabase.coordinate(ring:Int(a[0]),position:Int(a[1]))
            XCTAssertEqual(p.q,Int(a[2]));XCTAssertEqual(p.r,Int(a[3]))
        }
        for a in v.groupSwaps {
            XCTAssertEqual(OriginalLoungeGroupDatabase.improvesSwap(nodeA:.init(0,0),nodeB:.init(16,16),actorA:.init(Float(a[0]),Float(a[1])),actorB:.init(Float(a[2]),Float(a[3])),restrictionsA:UInt32(a[4])),a[5]==1)
        }
        for (i,a) in v.collisionReactions.enumerated() {
            let reaction=OriginalLounge.collisionReaction(delta:.init(Float(a[0]),Float(a[1])),forward:.init(0,1),velocity:.init(Float(a[2]),Float(a[3])),restrictions:UInt32(a[4]))
            XCTAssertEqual(reaction?.type ?? -1,Int(a[5]),"reaction fixture \(i)")
            XCTAssertEqual(reaction?.rate ?? 0,Float(a[6]),accuracy:2e-6,"rate fixture \(i)")
            var r=OriginalLoungeRandom(seed:42);XCTAssertEqual(120+r.below(180),UInt32(a[7]));XCTAssertEqual(r.words,a[8..<12].map {UInt32($0)})
        }
        for a in v.groupOptimizations {
            var db=OriginalLoungeGroupDatabase(),r=OriginalLoungeRandom(seed:UInt32(a[0]))
            let shift=Int(a[1]),positions=(0..<7).map {db.nodes[($0+shift)%7].position}
            for i in 0..<7 {_=db.insert(actor:i,at:i)}
            let result=db.optimize(from:0,positions:positions,restrictions:Array(repeating:0,count:7),random:&r)
            XCTAssertEqual(result,Int(a[2]));XCTAssertEqual(Array(db.nodes.prefix(7)).map {$0.actor!},a[3..<10].map {Int($0)})
            XCTAssertEqual(r.words,a[10..<14].map {UInt32($0)})
        }
        print("Verified \(v.locomotion.count+v.groupCoordinates.count+v.groupSwaps.count+v.collisionReactions.count+v.groupOptimizations.count) source state/group/reaction fixtures")
    }
}
