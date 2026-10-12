import XCTest
@testable import PlazaCore

final class PlazaEntranceTests:XCTestCase {
    private func crowd()->CrowdSimulation {
        var crowd=CrowdSimulation(population:160,localCount:3)
        crowd.groupsBelowIslands=true;crowd.minimumSpacing=0.016
        crowd.islandHalfWidth=0.05;crowd.islandTopClearance=0.06;crowd.islandBottomClearance=0.15
        crowd.islands=[CrowdPoint(0.2,0.2),CrowdPoint(0.5,0.1),CrowdPoint(0.8,0.2),CrowdPoint(0.8,0.65),CrowdPoint(0.5,0.7),CrowdPoint(0.2,0.65)]
        return crowd
    }
    func testEntranceRunsFromAboveAndSettlesWithoutJumping() {
        var crowd=crowd();let goals=crowd.walkers.map(\.position)
        crowd.beginEntrance()
        XCTAssertTrue(crowd.walkers.allSatisfy {$0.position.y<0})
        var running=false,spread=false
        for _ in 0..<220 {
            let before=crowd.walkers;crowd.step(1.0/30)
            for (i,w) in crowd.walkers.enumerated() {
                XCTAssertLessThan(hypot(w.position.x-before[i].position.x,w.position.y-before[i].position.y),0.035)
                running = running || w.state==1
            }
            if crowd.entranceElapsed.map({(2...3).contains($0)}) == true {
                spread = spread || (crowd.walkers.contains {$0.position.y>0.1} && crowd.walkers.contains {$0.position.y<0.05})
            }
        }
        XCTAssertTrue(running);XCTAssertTrue(spread);XCTAssertNil(crowd.entranceElapsed)
        for (i,w) in crowd.walkers.enumerated() {XCTAssertEqual(w.position,goals[i])}
    }
    func testSkippingEntranceRestoresEveryDestination() {
        var crowd=crowd();let goals=crowd.walkers.map(\.position)
        crowd.beginEntrance();crowd.step(0.1);crowd.finishEntrance()
        XCTAssertNil(crowd.entranceElapsed);XCTAssertEqual(crowd.walkers.map(\.position),goals)
        XCTAssertTrue(crowd.walkers.allSatisfy {$0.state==0 && $0.motion==0})
    }
    func testOriginalRendererUsesRunClipDuringEntrance() throws {
        let names=Set(OriginalLounge.animations.map(\.name))
        let catalog=try XCTUnwrap(OriginalLoungeCatalog(clips:names.sorted().map {.init(name:$0,frames:40,loop:$0.hasSuffix("_l"))}))
        var crowd=crowd();crowd.enableOriginalControllers(catalog);crowd.beginEntrance()
        crowd.step(0.1)
        XCTAssertEqual(crowd.originalSample(0)?.clip,catalog.clip(animation:4))
        for _ in 0..<220 {crowd.step(1.0/30)}
        XCTAssertNil(crowd.entranceElapsed)
        XCTAssertNotEqual(crowd.originalSample(0)?.clip,catalog.clip(animation:4))
    }
    func testIconsPopInAroundTheOvalBeforeCrowdFinishes() {
        let slots=[CrowdPoint(0.2,0.18),CrowdPoint(0.6,0.1),CrowdPoint(0.84,0.55),CrowdPoint(0.38,0.65)]
        XCTAssertGreaterThan(Set(slots.map {PlazaEntrance.iconDelay(at:$0)}).count,1)
        for slot in slots {
            XCTAssertEqual(PlazaEntrance.iconProgress(at:slot,elapsed:0),0)
            XCTAssertEqual(PlazaEntrance.iconProgress(at:slot,elapsed:3),1)
        }
        XCTAssertGreaterThan(PlazaEntrance.iconScale(progress:0.75),1)
        XCTAssertEqual(PlazaEntrance.iconScale(progress:1),1)
    }
}
