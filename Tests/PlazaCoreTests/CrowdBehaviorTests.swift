import XCTest
@testable import PlazaCore

final class CrowdBehaviorTests:XCTestCase {
    private let islands=[CrowdPoint(0.15,0.18),CrowdPoint(0.38,0.1),CrowdPoint(0.62,0.1),CrowdPoint(0.85,0.18),CrowdPoint(0.89,0.52),CrowdPoint(0.72,0.78),CrowdPoint(0.28,0.78),CrowdPoint(0.11,0.52)]
    func testGatheringRemainsSpacedMostlyStationaryAndUsesCompleteActivities() {
        var crowd=CrowdSimulation(population:60,localCount:3)
        crowd.worldAspect=1.25;crowd.islands=islands
        var moving=0,total=0,sits=0,activities=Set<CrowdActivity>(),close=0
        var sitStart:[Int:(CrowdPoint,Double)]=[:]
        for frame in 0..<5400 {
            let old=crowd.walkers;crowd.step(1.0/30)
            for (i,w) in crowd.walkers.enumerated() {
                activities.insert(w.activity)
                if frame>900 {total+=1;if w.speed>0.005 {moving+=1}}
                if w.activity == .sit {
                    if old[i].activity != .sit {sitStart[i]=(w.position,w.activityDuration);sits+=1}
                    if let start=sitStart[i] {XCTAssertEqual(w.position,start.0)}
                } else if old[i].activity == .sit {
                    XCTAssertGreaterThanOrEqual(old[i].activityTime+1.0/30,old[i].activityDuration-1e-8)
                    sitStart.removeValue(forKey:i)
                }
                if frame%30==0 {for j in 0..<i {if hypot(w.position.x-crowd.walkers[j].position.x,(w.position.y-crowd.walkers[j].position.y)/1.25)<0.028 {close+=1}}}
            }
        }
        let fraction=Double(moving)/Double(total)
        print("Crowd observation: walking fraction \(fraction), close pair samples \(close), seated activities \(sits)")
        XCTAssertGreaterThan(fraction,0.03);XCTAssertLessThan(fraction,0.40)
        XCTAssertLessThan(close,1000,"The crowd must not collapse into overlapping app piles")
        XCTAssertGreaterThan(sits,0);XCTAssertTrue(activities.isSuperset(of:[.wave,.talk,.listen,.lookAround,.scratch,.yawn,.sit,.bow]))
    }
    func testConversationTurnsFollowSourceClipDurationAndReleaseTogether() {
        var crowd=CrowdSimulation(population:60,localCount:3)
        crowd.islands=islands
        var turns=0,releases=0
        for _ in 0..<5400 {
            let old=crowd.walkers;crowd.step(1.0/30)
            for (i,w) in crowd.walkers.enumerated() {
                if let j=w.partner,j>i {
                    XCTAssertEqual(crowd.walkers[j].partner,i)
                    XCTAssertEqual(w.conversation,crowd.walkers[j].conversation,accuracy:1e-8)
                    if old[i].activity == .talk && w.activity == .listen {
                        XCTAssertEqual(old[i].activityTime+1.0/30,crowd.timing.talk,accuracy:0.07);turns+=1
                    }
                } else if let j=old[i].partner,j>i {
                    XCTAssertNil(crowd.walkers[j].partner);releases+=1
                }
            }
        }
        XCTAssertGreaterThan(turns,5);XCTAssertGreaterThan(releases,5)
    }
    func testInstalledClipTimingControlsGreetingAndAvoidsMidClipStarts() {
        var crowd=CrowdSimulation(population:1,localCount:1)
        crowd.timing=CrowdTiming(clips:["Handwaving00_o":1,"Handwaving00_l":0.8,"Handwaving00_oe":0.9])
        for _ in 0..<90 {crowd.step(1.0/30)}
        crowd.acknowledge(0)
        XCTAssertEqual(crowd.walkers[0].activityTime,0)
        XCTAssertEqual(crowd.walkers[0].activityDuration,3.5,accuracy:1e-9)
        let p=crowd.walkers[0].position
        for _ in 0..<104 {crowd.step(1.0/30)}
        XCTAssertEqual(crowd.walkers[0].activity,.wave);XCTAssertEqual(crowd.walkers[0].position,p)
        for _ in 0..<3 {crowd.step(1.0/30)}
        XCTAssertEqual(crowd.walkers[0].activity,.rest)
    }
}
