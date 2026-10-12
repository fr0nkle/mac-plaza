import XCTest
@testable import PlazaCore

final class CrowdContinuityTests:XCTestCase {
    private func catalog()->OriginalLoungeCatalog {
        OriginalLoungeCatalog(clips:Set(OriginalLounge.animations.map(\.name)).sorted().map {.init(name:$0,frames:40,loop:$0.hasSuffix("_l"))})!
    }
    func testRosterUpdatesPreserveActorsAndOriginalPlayback() {
        var crowd=CrowdSimulation(population:0,localCount:0,seed:42)
        let ids=(0..<40).map {_ in UUID()},catalog=catalog()
        crowd.islands=[.init(0.2,0.2),.init(0.8,0.2)];crowd.groupsBelowIslands=true
        crowd.enableOriginalControllers(catalog);crowd.reconcileRoster(ids,localCount:3)
        crowd.islands=[.init(0.2,0.2),.init(0.8,0.2)]
        for _ in 0..<600 {crowd.step(1.0/60)}
        let before=crowd.walkers,poses=ids.indices.map {crowd.originalSample($0)}
        crowd.enableOriginalControllers(catalog);crowd.reconcileRoster(ids,localCount:3)
        XCTAssertEqual(crowd.walkers,before);XCTAssertEqual(ids.indices.map {crowd.originalSample($0)},poses)
        let reversed=Array(ids.reversed());crowd.reconcileRoster(reversed,localCount:3)
        for i in reversed.indices {
            let old=ids.firstIndex(of:reversed[i])!
            XCTAssertEqual(crowd.walkers[i].position,before[old].position)
            XCTAssertEqual(crowd.walkers[i].originalMotion,before[old].originalMotion)
            XCTAssertEqual(crowd.originalSample(i),poses[old])
            if let j=crowd.walkers[i].partner {XCTAssertEqual(crowd.walkers[j].partner,i)}
        }
        let retained=crowd.walkers[30]
        crowd.reconcileRoster(Array(reversed.prefix(20)),localCount:3)
        crowd.reconcileRoster(reversed,localCount:3)
        XCTAssertEqual(crowd.walkers[30].position,retained.position)
        let oldPositions=crowd.walkers.map(\.position)
        crowd.reconcileRoster(reversed+[UUID()],localCount:4)
        XCTAssertEqual(Array(crowd.walkers.prefix(40)).map(\.position),oldPositions)
        XCTAssertEqual(crowd.walkers.count,41)
    }
    func testLayoutCoveringActorUsesContinuousEgress() {
        for original in [false,true] {
        var crowd=CrowdSimulation(population:1,localCount:1,seed:42)
        if original {crowd.enableOriginalControllers(catalog())}
        crowd.islands=[.init(0.1,0.1)];crowd.step(0.01)
        let p=crowd.walkers[0].position
        crowd.islandHalfWidth=0.04;crowd.islandTopClearance=0.04;crowd.islandBottomClearance=0.04
        crowd.islands=[p]
        XCTAssertEqual(crowd.walkers[0].position,p)
        var largest=0.0
        for _ in 0..<1800 {
            let old=crowd.walkers[0].position;crowd.step(1.0/60)
            let next=crowd.walkers[0].position;largest=max(largest,hypot(next.x-old.x,next.y-old.y))
        }
        XCTAssertLessThan(largest,0.005,"A layout update must not teleport a covered actor")
        let end=crowd.walkers[0].position
        XCTAssertTrue(abs(end.x-p.x)>=0.04 || abs(end.y-p.y)>=0.04,"Actor should walk out of newly overlapping controls")
        }
    }
    func testBootEntranceKeepsItsClockAndRanksDuringRosterChanges() {
        var crowd=CrowdSimulation(population:0,localCount:0,seed:42)
        let ids=(0..<12).map {_ in UUID()}
        crowd.enableOriginalControllers(catalog());crowd.reconcileRoster(ids,localCount:1)
        crowd.islands=[.init(0.2,0.2)];crowd.beginEntrance()
        crowd.step(0.1)
        let positions=crowd.walkers.map(\.position),samples=ids.indices.map {crowd.originalSample($0)}
        crowd.reconcileRoster(Array(ids.reversed()),localCount:1)
        XCTAssertEqual(crowd.walkers.map(\.position),Array(positions.reversed()))
        for i in ids.indices {
            let old=samples[ids.count-1-i],new=crowd.originalSample(i)
            XCTAssertEqual(new?.frame,old?.frame);XCTAssertEqual(new?.blend,old?.blend)
        }
        crowd.step(0.1)
        for i in ids.indices {XCTAssertLessThan(hypot(crowd.walkers[i].position.x-positions[ids.count-1-i].x,crowd.walkers[i].position.y-positions[ids.count-1-i].y),0.2)}
    }
}
