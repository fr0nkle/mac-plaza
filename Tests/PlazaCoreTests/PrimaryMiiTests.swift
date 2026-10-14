import XCTest
@testable import PlazaCore

final class PrimaryMiiTests:XCTestCase {
    private let icons:[CrowdPoint] = [
        .init(0.22,0.18),.init(0.40,0.105),.init(0.60,0.105),.init(0.78,0.18),
        .init(0.84,0.55),.init(0.625,0.67),.init(0.38,0.65),.init(0.165,0.55)
    ]
    private let ids=(0..<60).map {UUID(uuidString:String(format:"57415241-0000-4000-8000-%012llx",UInt64($0)))!}
    private func crowd(original:Bool)->CrowdSimulation {
        var crowd=CrowdSimulation(population:0,localCount:0,seed:42)
        crowd.worldWidth=48;crowd.worldAspect=0.9;crowd.groupsBelowIslands=true;crowd.minimumSpacing=0.016
        crowd.islandHalfWidth=0.05;crowd.islandTopClearance=0.075;crowd.islandBottomClearance=0.14
        crowd.nominalSpeed=0.011
        if original {
            let names=Set(OriginalLounge.animations.map(\.name)).sorted()
            crowd.enableOriginalControllers(OriginalLoungeCatalog(clips:names.map {.init(name:$0,frames:40,loop:$0.hasSuffix("_l"))})!)
        }
        crowd.reconcileRoster(ids,localCount:4);crowd.setPrimaryAvatar(ids[3]);crowd.islands=icons
        return crowd
    }
    private func centered(_ p:CrowdPoint)->Bool {hypot(p.x-0.5,p.y-0.55)<0.12}
    func testMainMiiLingersCentrallyVisitsAppsAndReturnsWithTheSameCrowd() {
        for original in [false,true] {
            var crowd=crowd(original:original)
            XCTAssertTrue(centered(crowd.walkers[3].position))
            var centralSamples=0,excursions=0,returns=0,visitedApps=false,away=false
            for frame in 0..<18000 {
                let previous=crowd.walkers[3].position;crowd.step(1.0/30)
                let p=crowd.walkers[3].position
                XCTAssertEqual(crowd.walkers.count,60)
                XCTAssertLessThan(hypot(p.x-previous.x,p.y-previous.y),0.006)
                if frame%30 != 0 {continue}
                if centered(p) {
                    centralSamples+=1
                    if away {returns+=1;away=false}
                } else if !away {excursions+=1;away=true}
                if icons.contains(where:{abs(p.x-$0.x)<0.10 && p.y>$0.y+0.12 && p.y<$0.y+0.27}) {visitedApps=true}
            }
            print("Primary Mii \(original ? "original":"fallback"): \(centralSamples)/600 seconds near center, \(excursions) outings, \(returns) returns")
            XCTAssertGreaterThan(centralSamples,300,"The main Mii should spend most of its time around the middle")
            XCTAssertGreaterThan(excursions,0,"It must be free to leave the middle")
            XCTAssertGreaterThan(returns,0,"It must return after an outing")
            XCTAssertTrue(visitedApps,"Outings should reach app gatherings")
        }
    }
    func testPrimaryIdentitySurvivesReorderingAndChangingItDoesNotRelocateMiis() {
        for original in [false,true] {
            var crowd=crowd(original:original)
            for _ in 0..<1800 {crowd.step(1.0/30)}
            let previous=crowd.walkers
            crowd.reconcileRoster(Array(ids.reversed()),localCount:4);crowd.setPrimaryAvatar(ids[3])
            XCTAssertEqual(crowd.primaryAvatarID,ids[3])
            XCTAssertEqual(crowd.walkers.map(\.position),previous.reversed().map(\.position))
            XCTAssertEqual(crowd.walkers.map(\.target),previous.reversed().map(\.target))
            let positions=crowd.walkers.map(\.position)
            let selected=crowd.walkers[49]
            crowd.setPrimaryAvatar(ids[10])
            XCTAssertEqual(crowd.walkers.map(\.position),positions)
            if selected.partner == nil {XCTAssertTrue(centered(crowd.walkers[49].target))}
            else {
                XCTAssertEqual(crowd.walkers[49].partner,selected.partner)
                XCTAssertEqual(crowd.walkers[49].conversation,selected.conversation,"Changing the main Mii must let an active conversation finish")
            }
            crowd.setPrimaryAvatar(nil)
            XCTAssertEqual(crowd.walkers.map(\.position),positions)
        }
    }
    func testCenterPreferenceAvoidsAppObstacles() {
        var crowd=crowd(original:false)
        let covered=crowd.walkers[3].position
        crowd.islands=[covered]
        let before=crowd.walkers.map(\.position)
        crowd.setPrimaryAvatar(nil);crowd.setPrimaryAvatar(ids[3])
        XCTAssertEqual(crowd.walkers.map(\.position),before)
        let target=crowd.walkers[3].target
        XCTAssertTrue(abs(target.x-covered.x)>=0.05 || target.y<=covered.y-0.075 || target.y>=covered.y+0.14)
        XCTAssertLessThan(hypot(target.x-0.5,target.y-0.55),0.20)
    }
    func testChoosingMainMiiDoesNotInterruptConversationAndItReturnsAfterward() {
        var placement=crowd(original:false).walkers
        for (i,j) in [(3,4),(4,3)] {
            placement[i].position = .init(0.21+Double(i-3)*0.025,0.38)
            placement[i].target=placement[i].position;placement[i].path=[]
            placement[i].partner=j;placement[i].conversation=3;placement[i].exchangeDuration=3
        }
        var simulation=CrowdSimulation(placement:placement,localCount:4,seed:42)
        simulation.worldWidth=48;simulation.worldAspect=0.9;simulation.minimumSpacing=0.016
        simulation.groupsBelowIslands=true;simulation.islandHalfWidth=0.05
        simulation.islandTopClearance=0.075;simulation.islandBottomClearance=0.14
        simulation.reconcileRoster(ids,localCount:4);simulation.islands=icons
        let previous=simulation.walkers
        simulation.setPrimaryAvatar(ids[3])
        XCTAssertEqual(simulation.walkers.map(\.position),previous.map(\.position))
        XCTAssertEqual(simulation.walkers[3].partner,4)
        XCTAssertEqual(simulation.walkers[4].partner,3)
        XCTAssertEqual(simulation.walkers[3].conversation,3)
        var returned=false
        for _ in 0..<3600 {simulation.step(1.0/30);returned = returned || centered(simulation.walkers[3].position)}
        XCTAssertTrue(returned,"The central home should take effect after the conversation finishes")
    }
}
