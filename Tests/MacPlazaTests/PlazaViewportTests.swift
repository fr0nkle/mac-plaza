import XCTest
import PlazaCore
@testable import MacPlaza

final class PlazaViewportTests: XCTestCase {
    @MainActor
    func testEntranceClockFreezesWhileHiddenAndCanSkipToTheFinishedPlaza() async {
        let clock=PlazaEntranceClock()
        XCTAssertEqual(clock.elapsed(at:Date()),0)
        clock.resume(at:2)
        XCTAssertEqual(clock.elapsed(at:Date()),2,accuracy:0.05)
        clock.pause()
        let frozen=clock.elapsed(at:Date())
        XCTAssertEqual(clock.elapsed(at:Date().addingTimeInterval(60)),frozen)
        clock.resume(at:3)
        XCTAssertEqual(clock.elapsed(at:Date()),3,accuracy:0.05)
        clock.finish();clock.resume(at:0)
        XCTAssertTrue(clock.finished);XCTAssertNil(clock.anchor)
        XCTAssertEqual(clock.elapsed(at:Date()),PlazaEntrance.duration)
    }
    @MainActor
    func testEntranceWaitsForRendererAndPlaysOnlyOnce() async throws {
        let scene=PlazaScene(size:CGSize(width:1200,height:720))
        scene.configure(avatars:[Avatar()],population:20)
        scene.beginEntrance(enabled:true)
        let owner=UUID();var latest:[[Double]]=[]
        scene.attachFFL(owner:owner,frame:{latest=$0},configure:{_ in})
        scene.setMoving(true)
        defer {scene.detachFFL(owner:owner)}
        try await Task.sleep(for:.milliseconds(120))
        let waiting=try XCTUnwrap(latest.first)
        XCTAssertNil(scene.entranceClock.anchor)
        scene.rendererDidBecomeReady()
        for _ in 0..<100 where scene.entranceClock.anchor == nil {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertNotNil(scene.entranceClock.anchor)
        XCTAssertNotEqual(latest.first?[1],waiting[1])
        scene.finishEntrance();let settled=latest
        scene.beginEntrance(enabled:true)
        XCTAssertTrue(scene.entranceClock.finished)
        XCTAssertEqual(latest,settled,"An editor or renderer replacement must not replay the boot sequence")
    }
    func testAppFocusKeepsEverySelectedAppAtTheSamePlazaPosition() {
        for size in [CGSize(width:1060,height:470),CGSize(width:1280,height:580),CGSize(width:1600,height:900)] {
            for count in [8,10,12] {
                for point in PlazaLayout.slots(for:count).prefix(count) {
                    let focus=PlazaViewport.appFocus(at:point,size:size)
                    XCTAssertTrue((1.8...2.1).contains(focus.zoom))
                    let x=size.width/2+(point.x-0.5)*size.width*focus.zoom+focus.offset.width
                    let y=size.height/2+(point.y-0.5)*size.height*focus.zoom+focus.offset.height
                    XCTAssertEqual(x,size.width*0.28,accuracy:0.001)
                    XCTAssertEqual(y,size.height*0.25,accuracy:0.001)
                }
            }
        }
    }
    func testSavedMiisJoinNaturalGroupsWithOngoingMovement() {
        var crowd=CrowdSimulation(population:60,localCount:3)
        crowd.minimumSpacing=0.025;crowd.groupsBelowIslands=true
        crowd.islandHalfWidth=0.05;crowd.islandTopClearance=0.06;crowd.islandBottomClearance=0.15
        crowd.islands=PlazaLayout.compactSlots.map { CrowdPoint($0.x,$0.y) }
        let start=Array(crowd.walkers.prefix(3)).map(\.position)
        let home=crowd.islands[0]
        for walker in crowd.walkers.prefix(3) {
            XCTAssertLessThan(abs(walker.position.x-home.x),0.11)
            XCTAssertGreaterThan(walker.position.y,home.y+crowd.islandBottomClearance)
            XCTAssertLessThanOrEqual(walker.wait,25)
        }
        var moved=Set<Int>()
        for _ in 0..<1800 {
            crowd.step(1.0/30)
            for index in 0..<3 where start[index] != crowd.walkers[index].position {moved.insert(index)}
        }
        XCTAssertFalse(moved.isEmpty,"Saved Miis should take part in the ongoing crowd, alongside quiet group members")
    }
    func testZoomAndPanKeepThePlazaReachable() {
        let size=CGSize(width:1280,height:580)
        XCTAssertEqual(PlazaViewport.zoom(0.1),0.75)
        XCTAssertEqual(PlazaViewport.zoom(3),1.75)
        XCTAssertEqual(PlazaViewport.offset(CGSize(width:500,height:-500),zoom:1,size:size),.zero)
        XCTAssertEqual(PlazaViewport.offset(CGSize(width:500,height:-500),zoom:1.5,size:size),CGSize(width:320,height:-145))
        XCTAssertEqual(PlazaViewport.offset(CGSize(width:-500,height:500),zoom:1.5,size:size),CGSize(width:-320,height:145))
    }
    func testReferenceCompositionLeavesVisitorsBelowEveryIcon() {
        for size in [CGSize(width:1060,height:470),CGSize(width:1280,height:580),CGSize(width:1600,height:900)] {
            for count in [8,10,12] {
                let slots=Array(PlazaLayout.slots(for:count).prefix(count))
                let tile=Double(PlazaLayout.tileSize(in:size))
                var crowd=CrowdSimulation(population:Preferences.defaultPopulation,localCount:3)
                crowd.worldWidth=PlazaLayout.worldWidth
                crowd.minimumSpacing=0.016
                crowd.groupsBelowIslands=true
                crowd.worldAspect=16/sqrt(740)*size.width/size.height
                crowd.islandHalfWidth=(tile/2+10)/size.width
                crowd.islandTopClearance=(tile/2+8)/size.height
                crowd.islandBottomClearance=(tile/2+32+size.width*0.035)/size.height
                crowd.islands=slots.map { CrowdPoint($0.x,$0.y) }
                for w in crowd.walkers {
                    XCTAssertTrue((0.05...0.95).contains(w.position.x))
                    XCTAssertTrue((0.20...0.95).contains(w.position.y))
                    XCTAssertFalse(slots.contains { abs(w.position.x-$0.x)<crowd.islandHalfWidth && w.position.y>$0.y-crowd.islandTopClearance && w.position.y<$0.y+crowd.islandBottomClearance })
                }
                let upper=crowd.walkers.filter { $0.position.y<0.55 }.count
                let lower=crowd.walkers.filter { $0.position.y>0.72 }.count
                XCTAssertGreaterThan(upper,10,"Groups should occupy the back of the plaza as well as the foreground")
                XCTAssertGreaterThan(lower,10)
                XCTAssertLessThanOrEqual(BubblePlanner.positions(size:size,islands:slots,limit:1).count,1)
            }
        }
    }
    func testFullerCrowdBalancesLooseGroupsAndOpenWalkways() {
        var crowd=CrowdSimulation(population:Preferences.defaultPopulation,localCount:3)
        crowd.worldWidth=48;crowd.worldAspect=1.3
        crowd.minimumSpacing=0.016;crowd.groupsBelowIslands=true
        crowd.islandHalfWidth=0.055;crowd.islandTopClearance=0.11;crowd.islandBottomClearance=0.23
        let slots=PlazaLayout.compactSlots
        crowd.islands=slots.map { CrowdPoint($0.x,$0.y) }
        XCTAssertEqual(crowd.walkers.count,160)
        func nearGroup(_ p:CrowdPoint,_ slot:CGPoint)->Bool {
            abs(p.x-slot.x)<0.105 && abs(p.y-min(0.90,slot.y+crowd.islandBottomClearance+0.045))<0.065
        }
        for slot in slots {
            let group=crowd.walkers.dropFirst(3).filter {nearGroup($0.position,slot)}
            XCTAssertGreaterThanOrEqual(group.count,6,"Every icon should retain a recognizable gathering")
            XCTAssertLessThan(group.count,22,"Visitors should spread beyond compact piles")
        }
        let between=crowd.walkers.dropFirst(3).filter {w in !slots.contains {nearGroup(w.position,$0)}}
        XCTAssertTrue((20...45).contains(between.count),"A minority should occupy open walkways while most visitors gather")
        var moving=0
        for frame in 0..<1800 {
            crowd.step(1.0/30)
            if frame>300 {moving+=crowd.walkers.filter {$0.speed>0.003}.count}
        }
        XCTAssertGreaterThan(Double(moving)/Double(1499*160),0.08,"Wandering should continue after the initial layout")
    }
}
