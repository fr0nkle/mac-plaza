import XCTest
@testable import PlazaCore

final class EndlessCrowdTests:XCTestCase {
    private let bounds=CrowdNavigationBounds(minX:-0.04,maxX:1.04,minY:0.02,maxY:0.98)
    private func crowd(from:CrowdPoint,to:CrowdPoint,original:Bool=false)->CrowdSimulation {
        var walker=CrowdWalker(position:from,target:to)
        walker.angle=from.x<to.x ? -.pi/2:.pi/2
        var crowd=CrowdSimulation(placement:[walker],localCount:0,seed:42)
        crowd.endlessWandering=true;crowd.worldWidth=48;crowd.worldAspect=1
        crowd.setNavigationBounds(bounds)
        if original {
            let names=Set(OriginalLounge.animations.map(\.name)).sorted()
            crowd.enableOriginalControllers(OriginalLoungeCatalog(clips:names.map {.init(name:$0,frames:40,loop:$0.hasSuffix("_l"))})!)
        }
        return crowd
    }
    func testBothDirectionsWrapAndContinueToTheAppDestination() {
        for original in [false,true] {for reversed in [false,true] {
            let from=CrowdPoint(reversed ? 0.98:0.02,0.50),to=CrowdPoint(reversed ? 0.05:0.95,0.50)
            var crowd=crowd(from:from,to:to,original:original)
            XCTAssertEqual(crowd.walkers[0].path.count,3)
            var wraps=0,reached=false
            for _ in 0..<1800 {
                let old=crowd.walkers[0];crowd.step(1.0/30);let w=crowd.walkers[0]
                if abs(w.position.x-old.position.x)>0.5 {
                    wraps+=1
                    XCTAssertEqual(w.position.y,old.position.y,accuracy:0.0001)
                    XCTAssertTrue(old.position.x<0 || old.position.x>1,"Leave the physical screen before wrapping")
                    XCTAssertTrue(w.position.x<0 || w.position.x>1,"Re-enter from offscreen")
                    XCTAssertLessThan(abs(w.phase-old.phase),0.2,"The seam must not add a screen-width of footfalls")
                }
                if hypot(w.position.x-to.x,w.position.y-to.y)<0.008 {reached=true;break}
            }
            XCTAssertEqual(wraps,1,"One crossing for original=\(original), reversed=\(reversed)")
            XCTAssertTrue(reached,"Continue after seam original=\(original), reversed=\(reversed): \(crowd.walkers[0])")
        }}
    }
    func testWrappingRouteAvoidsAppObstaclesAndUsesTheShorterSide() {
        var crowd=crowd(from:.init(0.1,0.5),to:.init(0.9,0.5))
        crowd.islandHalfWidth=0.06;crowd.islandTopClearance=0.08;crowd.islandBottomClearance=0.08
        crowd.islands=[.init(0,0.5),.init(1,0.5)]
        let path=crowd.route(from:.init(0.1,0.5),to:.init(0.9,0.5))
        XCTAssertFalse(path.isEmpty)
        var previous=CrowdPoint(0.1,0.5),length=0.0,crossings=0
        for p in path {
            if abs(p.x-previous.x)>1 {crossings+=1;XCTAssertEqual(p.y,previous.y)}
            else {
                length+=hypot(p.x-previous.x,p.y-previous.y)
                for t in 0...100 {
                    let sample=CrowdPoint(previous.x+(p.x-previous.x)*Double(t)/100,previous.y+(p.y-previous.y)*Double(t)/100)
                    XCTAssertFalse(crowd.islands.contains {abs(sample.x-$0.x)<0.06 && abs(sample.y-$0.y)<0.08})
                }
            }
            previous=p
        }
        XCTAssertEqual(crossings,1);XCTAssertLessThan(length,0.8)
    }
    func testActorsOutsideResizedCameraBoundsWalkBackIn() {
        for original in [false,true] {
            var crowd=crowd(from:.init(0.1,0.5),to:.init(0.5,0.5),original:original)
            crowd.setNavigationBounds(CrowdNavigationBounds(minX:0.25,maxX:0.75,minY:0.02,maxY:0.98))
            XCTAssertEqual(crowd.walkers[0].position,.init(0.1,0.5))
            var reached=false
            for _ in 0..<1800 {
                let old=crowd.walkers[0].position;crowd.step(1.0/30)
                XCTAssertLessThan(abs(crowd.walkers[0].position.x-old.x),0.01)
                if crowd.walkers[0].position.x>0.26 {reached=true;break}
            }
            XCTAssertTrue(reached,"Camera changes must not strand original=\(original) offscreen")
        }
    }
    func testCameraBoundsChangeDoesNotTeleportOrBreakAConversation() {
        var a=CrowdWalker(position:.init(0.1,0.4),target:.init(0.1,0.4))
        var b=CrowdWalker(position:.init(0.16,0.4),target:.init(0.16,0.4))
        a.partner=1;b.partner=0;a.conversation=10;b.conversation=10
        var crowd=CrowdSimulation(placement:[a,b],localCount:0,seed:1)
        crowd.endlessWandering=true
        crowd.setNavigationBounds(CrowdNavigationBounds(minX:0.25,maxX:0.75,minY:0.1,maxY:0.9))
        XCTAssertEqual(crowd.walkers,[a,b])
    }
    func testWanderersReachTheTopBottomAndBothSides() {
        var crowd=CrowdSimulation(population:60,localCount:0,seed:42)
        crowd.endlessWandering=true;crowd.groupsBelowIslands=true;crowd.minimumSpacing=0.016
        crowd.setNavigationBounds(bounds)
        crowd.islands=[.init(0.2,0.25),.init(0.8,0.25),.init(0.2,0.65),.init(0.8,0.65)]
        var top=false,bottom=false,left=false,right=false
        for _ in 0..<9000 {
            crowd.step(1.0/30)
            for w in crowd.walkers {
                top = top || w.position.y<0.16;bottom = bottom || w.position.y>0.91
                left = left || w.position.x<0.05;right = right || w.position.x>0.95
            }
        }
        XCTAssertTrue(top && bottom && left && right,"Wander across all four edges of the layout")
        XCTAssertGreaterThan(crowd.visitingIslands.count,10,"App groups should exchange visitors")
    }
}
